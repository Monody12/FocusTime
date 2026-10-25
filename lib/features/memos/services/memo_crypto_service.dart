import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/services/memo_private_payload.dart';
import 'package:focus_my_time/core/utils/debug_error_reporter.dart';
import 'package:hashlib/hashlib.dart' as hl;
import 'package:pointycastle/export.dart';

/// 隐私备忘录的端到端加密服务。
///
/// 服务端和同步数据库只会看到 [MemoDatabase] 中的包装密钥、算法参数和
/// 密文。密码派生密钥以及主密钥只在当前进程的短暂解锁会话中存在。
///
/// v18 起（OneNote 式文件夹锁）：每把锁（文件夹）有独立的内容密钥与解锁
/// 会话；旧的全局保险库在 v17 迁移后成为"默认锁"（同一把内容密钥），
/// 未迁移/未挂锁的存量隐私备忘录继续由默认锁的密钥解密。
class MemoCryptoService {
  MemoCryptoService._();

  static final MemoCryptoService instance = MemoCryptoService._();

  static const int _cryptoVersion = 1;
  static const String _kdfName = 'argon2id';
  static const int _kdfIterations = 3;
  static const int _kdfMemoryKiB = 64 * 1024;
  static const int _escrowIterations = 4;
  static const int _kdfLanes = 2;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const Duration defaultAutoLock = Duration(hours: 1);
  static const String _aad = 'focus-my-time/memo-vault/v1';

  final Random _random = Random.secure();
  final Map<String, Uint8List> _sessionKeys = <String, Uint8List>{};
  Timer? _autoLockTimer;
  Duration _autoLockDuration = defaultAutoLock;
  bool _lockOnBackground = true;
  DateTime? _lastActivity;

  /// 是否有任一锁处于解锁状态（旧 UI 的全局开关语义）。
  bool get isUnlocked => _sessionKeys.isNotEmpty;

  bool get lockOnBackground => _lockOnBackground;

  Future<bool> get isConfigured async =>
      (await MemoDatabase.getVault()) != null ||
      (await MemoDatabase.getLocks()).isNotEmpty;

  /// 默认锁（v17 迁移自旧保险库）当前是否已建立。
  Future<bool> get hasDefaultLock async =>
      (await MemoDatabase.getLock(MemoDatabase.defaultLockId)) != null;

  Duration get autoLockDuration => _autoLockDuration;

  /// 启动时恢复持久化的自动锁定偏好，失败时保持默认值。
  Future<void> loadPersistedSettings() async {
    try {
      final minutes = int.tryParse(
        await AppDatabase.getSetting('memoAutoLockMinutes') ?? '',
      );
      if (minutes != null && minutes > 0) {
        _autoLockDuration = Duration(minutes: minutes);
      }
      final background = await AppDatabase.getSetting('memoLockOnBackground');
      if (background != null) _lockOnBackground = background == 'true';
      _restorePersistedSessions();
    } catch (_) {
      // 偏好读取失败时保持默认值，不影响解锁会话。
    }
  }

  /// 恢复刷新前未过期的解锁会话（web sessionStorage）。
  ///
  /// 会话密钥按存储的过期时间精确生效：到期立即锁定，未到期则把
  /// [_lastActivity] 回拨到"剩余时间恰好等于原自动锁定时长"的位置，
  /// 让现有 [_armAutoLock] 的数学自然工作。
  void _restorePersistedSessions() {
    final sessions = restoreUnlockSessions();
    if (sessions.isEmpty) return;
    var restored = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    sessions.forEach((folderId, session) {
      final remainingMs = session.expiresAt - now;
      if (remainingMs <= 0) return;
      final key = Uint8List.fromList(
        base64Url.decode(session.keyBase64),
      );
      if (key.length != _keyLength) return;
      _sessionKeys[folderId] = key;
      restored++;
      final remaining = Duration(milliseconds: remainingMs);
      _lastActivity =
          DateTime.now().subtract(_autoLockDuration - remaining);
    });
    if (restored > 0) {
      debugLog('session', 'restored $restored unlock session(s)');
      _armAutoLock();
    }
  }

  // ---------------------------------------------------------------------------
  // 文件夹锁
  // ---------------------------------------------------------------------------

  bool isFolderUnlocked(String folderId) =>
      _sessionKeys.containsKey(folderId);

  /// 为文件夹设置锁密码。返回只显示一次的 Base32 恢复密钥。
  Future<String> setupFolderLock(String folderId, String password) async {
    _validatePassword(password);
    final existing = await MemoDatabase.getLockForFolder(folderId);
    if (existing != null) {
      throw StateError('该文件夹已设置锁密码，请使用修改密码或移除密码');
    }
    final salt = _randomBytes(_saltLength);
    final contentKey = _randomBytes(_keyLength);
    final recoveryKey = _randomBytes(_keyLength);
    final passwordKey = _deriveKey(password, salt);
    final wrappedByPassword = _seal(contentKey, passwordKey);
    final wrappedByRecovery = _seal(contentKey, recoveryKey);
    _zero(passwordKey);

    await MemoDatabase.saveLock({
      'id': _lockIdForNew(),
      'folderId': folderId,
      'kdfName': _kdfName,
      'kdfParams': jsonEncode({
        'iterations': _kdfIterations,
        'memoryKiB': _kdfMemoryKiB,
        'lanes': _kdfLanes,
        'keyLength': _keyLength,
      }),
      'salt': base64UrlEncode(salt),
      'wrappedContentKey': base64UrlEncode(wrappedByPassword.ciphertext),
      'wrapNonce': base64UrlEncode(wrappedByPassword.nonce),
      'recoveryWrappedContentKey': base64UrlEncode(wrappedByRecovery.ciphertext),
      'recoveryNonce': base64UrlEncode(wrappedByRecovery.nonce),
      'cryptoVersion': _cryptoVersion,
      'configRevision': 1,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    _setSessionKey(folderId, contentKey);
    return encodeRecoveryKey(recoveryKey);
  }

  /// 使用锁密码解锁文件夹。
  Future<bool> unlockFolderWithPassword(String folderId, String password) async {
    final lock = await MemoDatabase.getLockForFolder(folderId);
    debugLog('unlock', 'lookup folder=$folderId found=${lock != null}');
    if (lock == null) return false;
    try {
      _validatePassword(password);
      final salt = _decodeBase64(lock['salt']);
      final passwordKey = _deriveKey(password, salt);
      final contentKey = _open(
        ciphertext: _decodeBase64(lock['wrappedContentKey']),
        nonce: _decodeBase64(lock['wrapNonce']),
        key: passwordKey,
      );
      _zero(passwordKey);
      _setSessionKey(folderId, contentKey);
      debugLog('unlock', 'password ok folder=$folderId');
      return true;
    } catch (e) {
      debugLog('unlock', 'password FAILED folder=$folderId: $e');
      return false;
    }
  }

  /// 使用 Base32 恢复密钥解锁文件夹。
  Future<bool> unlockFolderWithRecoveryKey(
    String folderId,
    String recoveryKey,
  ) async {
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) return false;
    try {
      final key = decodeRecoveryKey(recoveryKey);
      final contentKey = _open(
        ciphertext: _decodeBase64(lock['recoveryWrappedContentKey']),
        nonce: _decodeBase64(lock['recoveryNonce']),
        key: key,
      );
      _zero(key);
      _setSessionKey(folderId, contentKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 使用账号托管密钥解锁文件夹（opt-in 的"忘记一切"找回路径）。
  Future<bool> unlockFolderWithEscrow(
    String folderId,
    Uint8List escrowKey,
  ) async {
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) return false;
    final wrapped = lock['escrowWrappedContentKey'] as String?;
    final nonce = lock['escrowNonce'] as String?;
    if (wrapped == null || wrapped.isEmpty || nonce == null || nonce.isEmpty) {
      return false;
    }
    try {
      final contentKey = _open(
        ciphertext: _decodeBase64(wrapped),
        nonce: _decodeBase64(nonce),
        key: Uint8List.fromList(escrowKey),
      );
      _setSessionKey(folderId, contentKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  void lockFolder(String folderId) {
    final key = _sessionKeys.remove(folderId);
    if (key != null) _zero(key);
    forgetUnlockSession(folderId);
    _rearmAutoLockIfNeeded();
  }

  /// 锁定全部解锁会话（自动锁定/切后台/手动"全部锁定"共用）。
  void lockAll() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    for (final key in _sessionKeys.values) {
      _zero(key);
    }
    _sessionKeys.clear();
    forgetAllUnlockSessions();
    _lastActivity = null;
  }

  /// 修改锁密码：仅重新包装同一个内容密钥，文件夹内密文无需重写。
  /// 要求该文件夹当前处于解锁状态（与 OneNote 一致）。
  Future<void> changeFolderLockPassword(
    String folderId,
    String newPassword,
  ) async {
    _validatePassword(newPassword);
    final currentKey = _sessionKeys[folderId];
    if (currentKey == null) throw StateError('请先解锁该文件夹');
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) throw StateError('该文件夹尚未设置锁密码');
    final salt = _randomBytes(_saltLength);
    final passwordKey = _deriveKey(newPassword, salt);
    final wrapped = _seal(currentKey, passwordKey);
    _zero(passwordKey);
    final revision =
        ((lock['configRevision'] as num?)?.toInt() ?? 0) + 1;
    await MemoDatabase.saveLock({
      ...lock,
      'salt': base64UrlEncode(salt),
      'wrappedContentKey': base64UrlEncode(wrapped.ciphertext),
      'wrapNonce': base64UrlEncode(wrapped.nonce),
      'configRevision': revision,
    });
    _touch();
  }

  /// 重新生成恢复密钥（旧的立即作废）。要求该文件夹处于解锁状态。
  Future<String> rotateRecoveryKey(String folderId) async {
    final currentKey = _sessionKeys[folderId];
    if (currentKey == null) throw StateError('请先解锁该文件夹');
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) throw StateError('该文件夹尚未设置锁密码');
    final recoveryKey = _randomBytes(_keyLength);
    final wrapped = _seal(currentKey, recoveryKey);
    final revision =
        ((lock['configRevision'] as num?)?.toInt() ?? 0) + 1;
    await MemoDatabase.saveLock({
      ...lock,
      'recoveryWrappedContentKey': base64UrlEncode(wrapped.ciphertext),
      'recoveryNonce': base64UrlEncode(wrapped.nonce),
      'configRevision': revision,
    });
    _touch();
    return encodeRecoveryKey(recoveryKey);
  }

  /// 开启账号托管：用托管密钥再包一层内容密钥（同步到服务器）。
  Future<void> enableEscrow(String folderId, Uint8List escrowKey) async {
    final currentKey = _sessionKeys[folderId];
    if (currentKey == null) throw StateError('请先解锁该文件夹');
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) throw StateError('该文件夹尚未设置锁密码');
    final nonce = _randomBytes(_nonceLength);
    final wrapped = _sealWithNonce(currentKey, escrowKey, nonce);
    final revision =
        ((lock['configRevision'] as num?)?.toInt() ?? 0) + 1;
    await MemoDatabase.saveLock({
      ...lock,
      'escrowWrappedContentKey': base64UrlEncode(wrapped.ciphertext),
      'escrowNonce': base64UrlEncode(nonce),
      'escrowParams': jsonEncode({
        'kdf': 'argon2id',
        'iterations': _escrowIterations,
        'memoryKiB': _kdfMemoryKiB,
        'lanes': _kdfLanes,
        'keyLength': _keyLength,
      }),
      'configRevision': revision,
    });
    _touch();
  }

  Future<void> disableEscrow(String folderId) async {
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) throw StateError('该文件夹尚未设置锁密码');
    final revision =
        ((lock['configRevision'] as num?)?.toInt() ?? 0) + 1;
    await MemoDatabase.saveLock({
      ...lock,
      'escrowWrappedContentKey': null,
      'escrowNonce': null,
      'escrowParams': null,
      'configRevision': revision,
    });
    _touch();
  }

  /// 移除文件夹锁（要求已解锁）。文件夹内备忘录全部转为普通明文备忘录。
  Future<int> removeFolderLock(String folderId) async {
    final currentKey = _sessionKeys[folderId];
    if (currentKey == null) throw StateError('请先解锁该文件夹');
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) throw StateError('该文件夹尚未设置锁密码');
    final memos = await MemoDatabase.getMemos(folderId: folderId);
    var converted = 0;
    for (final memo in memos) {
      final id = memo['id'] as String;
      final encrypted = memo['encryptedPayload'] as String?;
      if (memo['isPrivate'] == true && encrypted != null && encrypted.isNotEmpty) {
        try {
          final payload = decodeMemoPrivatePayload(
            decryptTextWithKey(encrypted, currentKey),
          );
          await MemoDatabase.updateMemo(id, {
            'title': payload.title,
            'bodyMd': payload.bodyMd,
            'isPrivate': false,
            'encryptTitle': false,
            'encryptedPayload': null,
          });
          converted++;
        } catch (_) {
          // 单条解密失败不阻断整体移除；该条保持原样并继续。
        }
      }
    }
    await MemoDatabase.deleteLock(lock['id'] as String);
    lockFolder(folderId);
    return converted;
  }

  /// 解析某条备忘录应使用的会话密钥：优先其所在文件夹的锁，其次默认锁
  /// （v17 迁移前/外的存量隐私备忘录与默认锁共用同一把内容密钥）。
  Uint8List? keyForMemoFolder(String? folderId) {
    if (folderId != null) {
      final key = _sessionKeys[folderId];
      if (key != null) return key;
    }
    return _sessionKeys[MemoDatabase.defaultPrivacyFolderId];
  }

  String encryptTextWithKey(String plaintext, Uint8List key) {
    final sealed = _seal(
      Uint8List.fromList(utf8.encode(plaintext)),
      Uint8List.fromList(key),
    );
    _touch();
    return jsonEncode({
      'v': _cryptoVersion,
      'n': base64UrlEncode(sealed.nonce),
      'c': base64UrlEncode(sealed.ciphertext),
    });
  }

  String decryptTextWithKey(String envelope, Uint8List key) {
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map || decoded['v'] != _cryptoVersion) {
        throw const FormatException('不支持的备忘录密文版本');
      }
      final bytes = _open(
        ciphertext: _decodeBase64(decoded['c']),
        nonce: _decodeBase64(decoded['n']),
        key: Uint8List.fromList(key),
      );
      _touch();
      return utf8.decode(bytes);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('隐私内容校验失败或密钥不正确');
    }
  }

  String _lockIdForNew() {
    // 默认锁固定 ID（v17 迁移）；新锁由调用方用文件夹锁服务生成。
    return 'memo-lock-${DateTime.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(0x7fffffff)}';
  }

  /// 初始化隐私密码。返回只显示一次的 Base32 恢复密钥。
  Future<String> setupPassword(String password) async {
    _validatePassword(password);
    final existing = await MemoDatabase.getVault();
    if (existing != null) {
      throw StateError('隐私密码已经设置，请使用修改密码或恢复流程');
    }

    final salt = _randomBytes(_saltLength);
    final masterKey = _randomBytes(_keyLength);
    final recoveryKey = _randomBytes(_keyLength);
    final passwordKey = _deriveKey(password, salt);
    final wrappedByPassword = _seal(masterKey, passwordKey);
    final wrappedByRecovery = _seal(masterKey, recoveryKey);

    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoDatabase.saveVault({
      'kdfName': _kdfName,
      'kdfParams': jsonEncode({
        'iterations': _kdfIterations,
        'memoryKiB': _kdfMemoryKiB,
        'lanes': _kdfLanes,
        'keyLength': _keyLength,
      }),
      'salt': base64UrlEncode(salt),
      'wrappedMasterKey': base64UrlEncode(wrappedByPassword.ciphertext),
      'wrapNonce': base64UrlEncode(wrappedByPassword.nonce),
      'recoveryWrappedMasterKey': base64UrlEncode(wrappedByRecovery.ciphertext),
      'recoveryNonce': base64UrlEncode(wrappedByRecovery.nonce),
      'cryptoVersion': _cryptoVersion,
      'configRevision': 1,
      'createdAt': now,
    });

    _setSession(masterKey);
    _zero(passwordKey);
    return encodeRecoveryKey(recoveryKey);
  }

  /// 使用隐私密码解锁。密码错误或保险库损坏时返回 false。
  Future<bool> unlockWithPassword(String password) async {
    final vault = await MemoDatabase.getVault();
    if (vault == null) return false;
    try {
      _validatePassword(password);
      final salt = _decodeBase64(vault['salt']);
      final passwordKey = _deriveKey(password, salt);
      final master = _open(
        ciphertext: _decodeBase64(vault['wrappedMasterKey']),
        nonce: _decodeBase64(vault['wrapNonce']),
        key: passwordKey,
      );
      _zero(passwordKey);
      _setSession(master);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 使用导出的 Base32 恢复密钥解锁。密钥无效或保险库损坏时返回 false。
  Future<bool> unlockWithRecoveryKey(String recoveryKey) async {
    final vault = await MemoDatabase.getVault();
    if (vault == null) return false;
    try {
      final key = decodeRecoveryKey(recoveryKey);
      final master = _open(
        ciphertext: _decodeBase64(vault['recoveryWrappedMasterKey']),
        nonce: _decodeBase64(vault['recoveryNonce']),
        key: key,
      );
      _zero(key);
      _setSession(master);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 修改（旧版全局保险库的）密码：只重新包装同一个主密钥，密文无需重写。
  /// 保留给迁移前的旧版本流程与测试使用；新 UI 使用 changeFolderLockPassword。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    final unlocked = isUnlocked || await unlockWithPassword(currentPassword);
    final master = _sessionKeys[MemoDatabase.defaultPrivacyFolderId];
    if (!unlocked || master == null) {
      throw StateError('当前隐私密码不正确');
    }
    final vault = await MemoDatabase.getVault();
    if (vault == null) throw StateError('隐私保险库尚未设置');
    final salt = _randomBytes(_saltLength);
    final key = _deriveKey(newPassword, salt);
    final wrapped = _seal(master, key);
    final revision = ((vault['configRevision'] as num?)?.toInt() ?? 0) + 1;
    await MemoDatabase.saveVault({
      ...vault,
      'salt': base64UrlEncode(salt),
      'wrappedMasterKey': base64UrlEncode(wrapped.ciphertext),
      'wrapNonce': base64UrlEncode(wrapped.nonce),
      'configRevision': revision,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _zero(key);
    _touch();
  }

  /// 对隐私正文、附件元数据或标题进行加密。
  String encryptText(String plaintext, {String? associatedData}) {
    final key = _requireSession();
    final sealed = _seal(
      Uint8List.fromList(utf8.encode(plaintext)),
      key,
      associatedData: associatedData,
    );
    _touch();
    return jsonEncode({
      'v': _cryptoVersion,
      'n': base64UrlEncode(sealed.nonce),
      'c': base64UrlEncode(sealed.ciphertext),
    });
  }

  String decryptText(String envelope, {String? associatedData}) {
    final key = _requireSession();
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map || decoded['v'] != _cryptoVersion) {
        throw const FormatException('不支持的备忘录密文版本');
      }
      final bytes = _open(
        ciphertext: _decodeBase64(decoded['c']),
        nonce: _decodeBase64(decoded['n']),
        key: key,
        associatedData: associatedData,
      );
      _touch();
      return utf8.decode(bytes);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('隐私内容校验失败或密钥不正确');
    }
  }

  /// 对二进制内容（附件等）用指定密钥加密，返回 JSON 信封。
  String encryptBytesWithKey(Uint8List plaintext, Uint8List key) {
    final sealed = _seal(plaintext, Uint8List.fromList(key));
    _touch();
    return jsonEncode({
      'v': _cryptoVersion,
      'n': base64UrlEncode(sealed.nonce),
      'c': base64UrlEncode(sealed.ciphertext),
    });
  }

  /// 用指定密钥解密 [encryptBytesWithKey] 产生的信封。
  Uint8List decryptBytesWithKey(String envelope, Uint8List key) {
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map || decoded['v'] != _cryptoVersion) {
        throw const FormatException('不支持的附件密文版本');
      }
      return _open(
        ciphertext: _decodeBase64(decoded['c']),
        nonce: _decodeBase64(decoded['n']),
        key: Uint8List.fromList(key),
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('附件密文校验失败或密钥不正确');
    }
  }

  /// 对二进制内容（附件等）进行加密，返回 JSON 信封。
  String encryptBytes(Uint8List plaintext) {
    final key = _requireSession();
    final sealed = _seal(plaintext, key);
    _touch();
    return jsonEncode({
      'v': _cryptoVersion,
      'n': base64UrlEncode(sealed.nonce),
      'c': base64UrlEncode(sealed.ciphertext),
    });
  }

  /// 解密 [encryptBytes] 产生的信封。解锁会话失效时抛出状态错误。
  Uint8List decryptBytes(String envelope) {
    final key = _requireSession();
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map || decoded['v'] != _cryptoVersion) {
        throw const FormatException('不支持的附件密文版本');
      }
      return _open(
        ciphertext: _decodeBase64(decoded['c']),
        nonce: _decodeBase64(decoded['n']),
        key: key,
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('附件密文校验失败或密钥不正确');
    }
  }

  /// 旧的全局锁定入口：等价于"全部锁定"（每个解锁会话独立清零）。
  void lock() => lockAll();

  void setAutoLockDuration(Duration duration) {
    if (duration <= Duration.zero) {
      throw const FormatException('自动锁定时间必须大于 0');
    }
    _autoLockDuration = duration;
    if (isUnlocked) _armAutoLock();
  }

  /// 设置应用切后台时是否立即锁定。关闭后仍会受无操作计时器保护。
  void setLockOnBackground(bool enabled) {
    _lockOnBackground = enabled;
    if (enabled && isUnlocked) {
      _touch();
    }
  }

  void onAppBackground() {
    // 默认进入后台立即锁定，只有用户明确选择延迟时才保留会话。
    if (isUnlocked && _lockOnBackground) lock();
  }

  void onAppResumed() {
    if (isUnlocked) _touch();
  }

  void touch() {
    if (isUnlocked) _touch();
  }

  /// Base32 恢复密钥编码，不包含容易混淆的 0、1 字符。
  static String encodeRecoveryKey(
    Uint8List key, {
    bool clearAfterEncode = true,
  }) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var buffer = 0;
    var bits = 0;
    final output = StringBuffer();
    for (final byte in key) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        output.write(alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) output.write(alphabet[(buffer << (5 - bits)) & 31]);
    if (clearAfterEncode) _zero(key);
    return output.toString();
  }

  static Uint8List decodeRecoveryKey(String value) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final normalized = value
        .toUpperCase()
        .replaceAll(RegExp(r'[-\s]'), '')
        .replaceAll('0', 'O')
        .replaceAll('1', 'I');
    if (normalized.length != 52) {
      throw const FormatException('恢复密钥长度无效');
    }
    var buffer = 0;
    var bits = 0;
    final output = <int>[];
    for (final char in normalized.split('')) {
      final index = alphabet.indexOf(char);
      if (index < 0) throw const FormatException('恢复密钥包含无效字符');
      buffer = (buffer << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        output.add((buffer >> bits) & 0xff);
      }
    }
    if (output.length != _keyLength) {
      throw const FormatException('恢复密钥长度无效');
    }
    return Uint8List.fromList(output);
  }

  /// 旧 API 的会话密钥：即默认锁（v17 迁移后的默认文件夹）的密钥。
  Uint8List _requireSession() {
    final key = _sessionKeys[MemoDatabase.defaultPrivacyFolderId];
    if (key == null) throw StateError('请先解锁隐私备忘录');
    return key;
  }

  void _setSession(Uint8List key) {
    lockAll();
    _sessionKeys[MemoDatabase.defaultPrivacyFolderId] = Uint8List.fromList(key);
    _zero(key);
    _touch();
  }

  void _setSessionKey(String folderId, Uint8List key) {
    final keyCopy = Uint8List.fromList(key);
    _zero(key);
    _sessionKeys[folderId] = keyCopy;
    // OneNote 语义：解锁保持到自动锁定超时，页面刷新（web）不丢会话。
    persistUnlockSession(
      folderId,
      base64UrlEncode(keyCopy),
      DateTime.now().millisecondsSinceEpoch + _autoLockDuration.inMilliseconds,
    );
    _touch();
  }

  void _rearmAutoLockIfNeeded() {
    if (_sessionKeys.isNotEmpty) {
      _touch();
    } else {
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
      _lastActivity = null;
    }
  }

  void _touch() {
    _lastActivity = DateTime.now();
    _armAutoLock();
  }

  void _armAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(_autoLockDuration, () {
      final last = _lastActivity;
      if (last == null ||
          DateTime.now().difference(last) >= _autoLockDuration) {
        lockAll();
      } else {
        _armAutoLock();
      }
    });
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  static void _validatePassword(String password) {
    if (password.length < 8) {
      throw const FormatException('隐私密码至少需要 8 个字符');
    }
  }

  /// Argon2id 密钥派生（RFC 9106）。
  ///
  /// 1.11.2 起改用 hashlib 优化实现：与原 pointycastle 输出逐字节一致
  /// （已做 RFC 合规性对比测试），派生耗时约为原来的 1/3（native 1.5s →
  /// 0.55s，web 端改善更明显）。老密文与包装记录无需任何迁移。
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final sw = Stopwatch()..start();
    final digest = hl.Argon2(
      type: hl.Argon2Type.argon2id,
      version: hl.Argon2Version.v13,
      parallelism: _kdfLanes,
      memorySizeKB: _kdfMemoryKiB,
      iterations: _kdfIterations,
      hashLength: _keyLength,
      salt: salt,
    ).convert(Uint8List.fromList(utf8.encode(password)));
    sw.stop();
    debugLog('kdf', 'argon2id derived in ${sw.elapsedMilliseconds}ms');
    return Uint8List.fromList(digest.bytes);
  }

  static _Sealed _seal(
    Uint8List plaintext,
    Uint8List key, {
    String? associatedData,
  }) {
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (index) => Random.secure().nextInt(256)),
    );
    return _sealWithNonce(plaintext, key, nonce, associatedData: associatedData);
  }

  static _Sealed _sealWithNonce(
    Uint8List plaintext,
    Uint8List key,
    Uint8List nonce, {
    String? associatedData,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List.fromList(utf8.encode(associatedData ?? _aad)),
        ),
      );
    return _Sealed(nonce, cipher.process(plaintext));
  }

  static Uint8List _open({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List key,
    String? associatedData,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(associatedData ?? _aad)),
        ),
      );
    return cipher.process(ciphertext);
  }

  static Uint8List _decodeBase64(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('密文格式无效');
    }
    return Uint8List.fromList(base64Url.decode(value));
  }

  static void _zero(Uint8List value) {
    for (var i = 0; i < value.length; i++) {
      value[i] = 0;
    }
  }
}

class _Sealed {
  const _Sealed(this.nonce, this.ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;
}
