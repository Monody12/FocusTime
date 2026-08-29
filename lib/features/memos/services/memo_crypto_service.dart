import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:pointycastle/export.dart';

/// 隐私备忘录的端到端加密服务。
///
/// 服务端和同步数据库只会看到 [MemoDatabase] 中的包装密钥、算法参数和
/// 密文。密码派生密钥以及主密钥只在当前进程的短暂解锁会话中存在。
class MemoCryptoService {
  MemoCryptoService._();

  static final MemoCryptoService instance = MemoCryptoService._();

  static const int _cryptoVersion = 1;
  static const String _kdfName = 'argon2id';
  static const int _kdfIterations = 3;
  static const int _kdfMemoryKiB = 64 * 1024;
  static const int _kdfLanes = 2;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const Duration defaultAutoLock = Duration(hours: 1);
  static const String _aad = 'focus-my-time/memo-vault/v1';

  final Random _random = Random.secure();
  Uint8List? _masterKey;
  Timer? _autoLockTimer;
  Duration _autoLockDuration = defaultAutoLock;
  bool _lockOnBackground = true;
  DateTime? _lastActivity;

  bool get isUnlocked => _masterKey != null;

  bool get lockOnBackground => _lockOnBackground;

  Future<bool> get isConfigured async =>
      (await MemoDatabase.getVault()) != null;

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
    } catch (_) {
      // 偏好读取失败时保持默认值，不影响解锁会话。
    }
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

  /// 修改密码时只重新包装同一个主密钥，已有备忘录密文无需重写。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    final unlocked = isUnlocked || await unlockWithPassword(currentPassword);
    if (!unlocked || _masterKey == null) {
      throw StateError('当前隐私密码不正确');
    }
    final vault = await MemoDatabase.getVault();
    if (vault == null) throw StateError('隐私保险库尚未设置');
    final salt = _randomBytes(_saltLength);
    final key = _deriveKey(newPassword, salt);
    final wrapped = _seal(_masterKey!, key);
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

  void lock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    if (_masterKey != null) _zero(_masterKey!);
    _masterKey = null;
    _lastActivity = null;
  }

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

  Uint8List _requireSession() {
    final key = _masterKey;
    if (key == null) throw StateError('请先解锁隐私备忘录');
    return key;
  }

  void _setSession(Uint8List key) {
    lock();
    _masterKey = Uint8List.fromList(key);
    _zero(key);
    _touch();
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
        lock();
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

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final generator = Argon2BytesGenerator();
    generator.init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: _keyLength,
        iterations: _kdfIterations,
        memory: _kdfMemoryKiB,
        lanes: _kdfLanes,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
    final output = Uint8List(_keyLength);
    generator.deriveKey(
      Uint8List.fromList(utf8.encode(password)),
      0,
      output,
      0,
    );
    return output;
  }

  static _Sealed _seal(
    Uint8List plaintext,
    Uint8List key, {
    String? associatedData,
  }) {
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (index) => Random.secure().nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          nonce,
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
