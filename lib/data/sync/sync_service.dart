import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/database/app_database.dart';

class SyncService {
  // 默认服务器地址
  static const _defaultServerUrl = String.fromEnvironment(
    'SYNC_SERVER_URL',
    defaultValue: 'https://focus.dluserver.cn',
  );

  // 内存中缓存的同步配置和凭证
  static String _serverUrl = _defaultServerUrl;
  static String _token = '';
  static String _userId = '';
  static String _username = '';
  static String _fakePassword = ''; // 用于在 UI 中显示的虚拟密码
  static String _realPassword = ''; // 真实的密码明文缓存
  static int _lastSyncTime = 0; // 本地成功同步时间，用于筛选本机待上传变更
  static int _lastServerSyncCursor = 0; // 服务端权威变更游标，用于拉取远端增量
  static String? _lastSyncError;
  static bool _syncing = false; // 防止并发同步
  static bool _syncRequested = false; // 同步过程中如有新请求，结束后补跑一次
  static Completer<({bool success, bool tokenExpired})>? _activeSyncCompleter;
  static Timer? _debouncedSyncTimer;
  static Timer? _autoSyncTimer;
  static final ValueNotifier<String> _syncWarningNotifier =
      ValueNotifier<String>('');
  static final Set<FutureOr<void> Function()> _syncCompletedListeners = {};

  static const String _encryptionKey = 'FocusMyTimeSecretKey!';
  static const String _fakePasswordMask = '••••••••';

  static String _encrypt(String text) {
    if (text.isEmpty) return '';
    final bytes = utf8.encode(text);
    final keyBytes = utf8.encode(_encryptionKey);
    final encrypted = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return base64.encode(encrypted);
  }

  static String _decrypt(String base64text) {
    if (base64text.isEmpty) return '';
    try {
      final bytes = base64.decode(base64text);
      final keyBytes = utf8.encode(_encryptionKey);
      final decrypted = List<int>.generate(
        bytes.length,
        (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
      );
      return utf8.decode(decrypted);
    } catch (_) {
      return '';
    }
  }

  // 仅供测试使用
  static String encryptForTesting(String text) => _encrypt(text);
  static String decryptForTesting(String base64text) => _decrypt(base64text);

  static Future<void> init() async {
    // 从本地数据库加载同步配置
    final serverUrl = await AppDatabase.getSetting('syncServerUrl');
    if (serverUrl != null) {
      try {
        _serverUrl = _normalizeServerUrl(serverUrl);
      } on FormatException {
        _serverUrl = _defaultServerUrl;
      }
    }

    final token = await AppDatabase.getSetting('syncToken');
    if (token != null) _token = token;

    final userId = await AppDatabase.getSetting('syncUserId');
    if (userId != null) _userId = userId;

    // 加载保存的用户名和虚拟密码，用于在重启后保持 UI 状态
    final username = await AppDatabase.getSetting('syncUsername');
    if (username != null) _username = username;

    final fakePassword = await AppDatabase.getSetting('syncFakePassword');
    if (fakePassword != null) _fakePassword = fakePassword;

    final realPasswordEncrypted = await AppDatabase.getSetting(
      'syncRealPassword',
    );
    if (realPasswordEncrypted != null) {
      _realPassword = _decrypt(realPasswordEncrypted);
    }

    final lastSync = await AppDatabase.getSetting('lastSyncTime');
    if (lastSync != null) _lastSyncTime = int.tryParse(lastSync) ?? 0;

    final serverCursor = await AppDatabase.getSetting('lastServerSyncCursor');
    if (serverCursor != null) {
      _lastServerSyncCursor = int.tryParse(serverCursor) ?? 0;
    } else {
      _lastServerSyncCursor = _lastSyncTime;
    }

    if (_token.isEmpty && _username.isNotEmpty) {
      _setSyncWarning('同步登录已失效，请在设置中重新登录');
    }

    // 数据恢复检测：如果 DB 被意外清空但 lastSyncTime 非零，
    // 重置为 0 以触发全量同步从服务器恢复数据
    await _recoverIfDataLost();
  }

  /// 检测到数据库被清空时自动重置 lastSyncTime，确保下次同步从服务器全量拉取
  static Future<void> _recoverIfDataLost() async {
    if (_lastSyncTime == 0) return;
    try {
      final db = await AppDatabase.database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM tasks WHERE deleted = 0',
      );
      final taskCount = (result.first['cnt'] as int?) ?? 0;
      if (taskCount == 0) {
        _lastSyncTime = 0;
        _lastServerSyncCursor = 0;
        await AppDatabase.setSetting('lastSyncTime', '0');
        await AppDatabase.setSetting('lastServerSyncCursor', '0');
      }
    } catch (_) {
      // 恢复检测失败不影响正常启动
    }
  }

  static String get serverUrl => _serverUrl;
  static String get token => _token;
  static String get userId => _userId;
  static String get username => _username;
  static String get fakePassword => _fakePassword;
  static String get realPassword => _realPassword;
  static int get lastSyncTime => _lastSyncTime;
  static int get lastServerSyncCursor => _lastServerSyncCursor;
  static String? get lastSyncError => _lastSyncError;
  static ValueListenable<String> get syncWarningListenable =>
      _syncWarningNotifier;
  static String get syncWarning => _syncWarningNotifier.value;

  static void addSyncCompletedListener(FutureOr<void> Function() listener) {
    _syncCompletedListeners.add(listener);
  }

  static void removeSyncCompletedListener(FutureOr<void> Function() listener) {
    _syncCompletedListeners.remove(listener);
  }

  static Future<void> setServerUrl(String url) async {
    final normalized = _normalizeServerUrl(url);
    _serverUrl = normalized;
    await AppDatabase.setSetting('syncServerUrl', normalized);
  }

  static String _normalizeServerUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的同步服务器地址');
    }
    final isLocalHost = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (kIsWeb && uri.scheme != 'https' && !isLocalHost) {
      throw const FormatException('浏览器版同步服务器必须使用 HTTPS');
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  static Map<String, dynamic>? _decodeResponseObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static String _friendlyRequestError(Object error, String action) {
    if (error is TimeoutException) {
      return '$action超时，请检查网络后重试';
    }
    if (error is http.ClientException) {
      return '无法连接同步服务器，请检查网络和服务器地址';
    }
    if (error is FormatException) {
      return error.message;
    }
    return '$action失败，请稍后重试';
  }

  static Future<void> _saveToken(
    String token,
    String userId, {
    String? username,
    String? password,
  }) async {
    _token = token;
    _userId = userId;
    await AppDatabase.setSetting('syncToken', token);
    await AppDatabase.setSetting('syncUserId', userId);

    // 如果提供了用户名，说明是登录或注册成功，保存用户名和虚拟密码
    if (username != null) {
      _username = username;
      _fakePassword = _fakePasswordMask; // 使用固定长度掩码，避免暴露真实密码长度
      await AppDatabase.setSetting('syncUsername', _username);
      await AppDatabase.setSetting('syncFakePassword', _fakePassword);
    }

    // 如果提供了密码，说明是登录或注册成功，保存真实密码的加密版本
    if (password != null) {
      _realPassword = password;
      final encrypted = _encrypt(password);
      await AppDatabase.setSetting('syncRealPassword', encrypted);
    }

    _setSyncWarning('');
  }

  static Future<void> _clearSession({
    required bool clearSavedCredentials,
  }) async {
    _token = '';
    _userId = '';
    await AppDatabase.setSetting('syncToken', '');
    await AppDatabase.setSetting('syncUserId', '');
    if (clearSavedCredentials) {
      _username = '';
      _fakePassword = '';
      _realPassword = '';
      await AppDatabase.setSetting('syncUsername', '');
      await AppDatabase.setSetting('syncFakePassword', '');
      await AppDatabase.setSetting('syncRealPassword', '');
      _setSyncWarning('');
    }
  }

  static Future<
    ({bool success, bool tokenExpired, String? error, String? userId})
  >
  register({required String username, required String password}) async {
    try {
      final normalizedUsername = username.trim();
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': normalizedUsername,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeResponseObject(response.body);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data?['success'] == true &&
          data?['token'] is String &&
          data?['userId'] is String) {
        final token = data!['token'] as String;
        final userId = data['userId'] as String;
        // 注册成功，保存登录凭证和用户信息
        await _saveToken(
          token,
          userId,
          username: normalizedUsername,
          password: password,
        );
        return (
          success: true,
          tokenExpired: false,
          error: null,
          userId: userId,
        );
      }
      return (
        success: false,
        tokenExpired: false,
        error:
            data?['error']?.toString() ??
            (response.statusCode >= 500 ? '同步服务暂时不可用' : '注册失败'),
        userId: null,
      );
    } catch (e) {
      return (
        success: false,
        tokenExpired: false,
        error: _friendlyRequestError(e, '注册'),
        userId: null,
      );
    }
  }

  static Future<
    ({bool success, bool tokenExpired, String? error, String? userId})
  >
  login({required String username, required String password}) async {
    try {
      final normalizedUsername = username.trim();
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': normalizedUsername,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeResponseObject(response.body);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data?['success'] == true &&
          data?['token'] is String &&
          data?['userId'] is String) {
        final token = data!['token'] as String;
        final userId = data['userId'] as String;
        // 登录成功，保存登录凭证和用户信息
        await _saveToken(
          token,
          userId,
          username: normalizedUsername,
          password: password,
        );
        return (
          success: true,
          tokenExpired: false,
          error: null,
          userId: userId,
        );
      }
      return (
        success: false,
        tokenExpired: false,
        error:
            data?['error']?.toString() ??
            (response.statusCode >= 500 ? '同步服务暂时不可用' : '登录失败'),
        userId: null,
      );
    } catch (e) {
      return (
        success: false,
        tokenExpired: false,
        error: _friendlyRequestError(e, '登录'),
        userId: null,
      );
    }
  }

  /// 登出：清除内存中的凭证并重置本地存储
  static Future<void> logout() async {
    await _clearSession(clearSavedCredentials: true);
  }

  /// 检查当前是否已登录（通过判断是否有 Token）
  static bool get isLoggedIn => _token.isNotEmpty;

  /// 更新本地记录的上次同步时间
  static Future<void> updateLastSyncTime({
    int? serverCursor,
    int? localSyncTime,
  }) async {
    _lastSyncTime = localSyncTime ?? DateTime.now().millisecondsSinceEpoch;
    if (serverCursor != null && serverCursor > _lastServerSyncCursor) {
      _lastServerSyncCursor = serverCursor;
      await AppDatabase.setSetting(
        'lastServerSyncCursor',
        _lastServerSyncCursor.toString(),
      );
    }
    await AppDatabase.setSetting('lastSyncTime', _lastSyncTime.toString());
  }

  /// A restored backup may contain records older than the previous local
  /// watermark. Reset both cursors so the next sync reconciles the full data
  /// set while keeping the current device's login credentials.
  static Future<void> resetCursorsAfterRestore() async {
    _lastSyncTime = 0;
    _lastServerSyncCursor = 0;
    _lastSyncError = null;
    await AppDatabase.setSetting('lastSyncTime', '0');
    await AppDatabase.setSetting('lastServerSyncCursor', '0');
  }

  /// 执行完整同步流程：上传本地变更 -> 下载远程变更
  static Future<({bool success, bool tokenExpired})> fullSync({
    bool notifyListeners = true,
  }) async {
    _setLastSyncError(null);
    if (!isLoggedIn) {
      _setLastSyncError('未登录或登录已失效');
      return (success: false, tokenExpired: false);
    }

    if (_syncing) {
      _syncRequested = true;
      final activeSync = _activeSyncCompleter;
      if (activeSync != null) {
        return activeSync.future;
      }
      return (success: false, tokenExpired: false);
    }

    _syncing = true;
    final completer = Completer<({bool success, bool tokenExpired})>();
    _activeSyncCompleter = completer;
    var syncResult = (success: false, tokenExpired: false);
    try {
      final localSyncCutoff = DateTime.now().millisecondsSinceEpoch;
      // Upload local changes
      final uploadResult = await _syncToServer();
      if (!uploadResult.success) {
        if (uploadResult.tokenExpired == true) {
          _setLastSyncError(syncWarning.isNotEmpty ? syncWarning : '登录已过期');
        }
        syncResult = (
          success: false,
          tokenExpired: uploadResult.tokenExpired ?? false,
        );
        return syncResult;
      }

      // Download remote changes using the server-side cursor. Local dirty
      // records still use _lastSyncTime because those timestamps are local.
      final downloadResult = await _downloadFromServer(_lastServerSyncCursor);
      if (!downloadResult.success) {
        if (downloadResult.tokenExpired == true) {
          _setLastSyncError(syncWarning.isNotEmpty ? syncWarning : '登录已过期');
        }
        syncResult = (
          success: false,
          tokenExpired: downloadResult.tokenExpired ?? false,
        );
        return syncResult;
      }

      await updateLastSyncTime(
        serverCursor:
            downloadResult.serverLastSync ?? uploadResult.serverLastSync,
        localSyncTime: localSyncCutoff,
      );
      if (notifyListeners) {
        await _notifySyncCompleted();
      }
      syncResult = (success: true, tokenExpired: false);
      return syncResult;
    } catch (e) {
      _setLastSyncError('同步异常: $e');
      syncResult = (success: false, tokenExpired: false);
      return syncResult;
    } finally {
      if (!completer.isCompleted) {
        completer.complete(syncResult);
      }
      _activeSyncCompleter = null;
      _syncing = false;
      if (_syncRequested) {
        _scheduleQueuedSync(Duration.zero);
      }
    }
  }

  static void _setSyncWarning(String message) {
    if (_syncWarningNotifier.value == message) return;
    _syncWarningNotifier.value = message;
  }

  static void _setLastSyncError(String? message) {
    _lastSyncError = message;
  }

  static String _serverErrorMessage(String stage, http.Response response) {
    final decoded = _decodeResponseObject(response.body);
    var detail = decoded?['error']?.toString() ?? '';
    if (detail.isEmpty) {
      detail = response.statusCode >= 500 ? '同步服务暂时不可用' : '请求被服务器拒绝';
    }
    if (detail.length > 180) {
      detail = '${detail.substring(0, 180)}...';
    }
    return '$stage 失败: HTTP ${response.statusCode} $detail';
  }

  static Future<bool> _tryAutoLogin() async {
    if (_username.isEmpty || _realPassword.isEmpty) {
      await _markAuthExpired('同步登录已失效，请在设置中重新登录');
      _setLastSyncError(syncWarning);
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': _username,
              'password': _realPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeResponseObject(response.body);
      if (response.statusCode == 200 &&
          data?['success'] == true &&
          data?['token'] is String &&
          data?['userId'] is String) {
        await _saveToken(data!['token'] as String, data['userId'] as String);
        return true;
      }

      await _markAuthExpired('自动重新登录失败，请在设置中确认密码后重新登录');
      _setLastSyncError(syncWarning);
      return false;
    } catch (_) {
      await _markAuthExpired('自动重新登录失败，请检查网络后在设置中重新登录');
      _setLastSyncError(syncWarning);
      return false;
    }
  }

  static Future<void> _markAuthExpired(String message) async {
    await _clearSession(clearSavedCredentials: false);
    if (_username.isNotEmpty && _fakePassword.isEmpty) {
      _fakePassword = _fakePasswordMask;
      await AppDatabase.setSetting('syncFakePassword', _fakePassword);
    }
    _setSyncWarning(message);
    stopAutoSync();
  }

  static Future<void> _notifySyncCompleted() async {
    for (final listener in List<FutureOr<void> Function()>.from(
      _syncCompletedListeners,
    )) {
      try {
        await Future.sync(listener);
      } catch (_) {
        // 后处理失败不能影响同步结果，调用方会在对应模块记录细节。
      }
    }
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})>
  _syncToServer({bool allowAutoLogin = true}) async {
    try {
      final payload = await AppDatabase.getSyncPayload(_lastSyncTime);

      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/sync'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'lastSyncTime': _lastServerSyncCursor,
              'tables': payload,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) {
        if (allowAutoLogin && await _tryAutoLogin()) {
          return _syncToServer(allowAutoLogin: false);
        }
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setLastSyncError(_serverErrorMessage('上传同步', response));
        return (success: false, tokenExpired: false, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true || data['serverLastSync'] != null) {
        return (
          success: true,
          tokenExpired: false,
          serverLastSync: data['serverLastSync'] as int?,
        );
      }
      _setLastSyncError('上传同步失败: 服务器响应缺少 serverLastSync');
      return (success: false, tokenExpired: false, serverLastSync: null);
    } catch (e) {
      _setLastSyncError(_friendlyRequestError(e, '上传同步'));
      return (success: false, tokenExpired: null, serverLastSync: null);
    }
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})>
  _downloadFromServer(
    int syncTimeForDownload, {
    bool allowAutoLogin = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/sync'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'lastSyncTime': syncTimeForDownload,
              'tables': {
                'lists': [],
                'tasks': [],
                'sessions': [],
                'task_recurrence_completions': [],
                'settings': [],
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        if (allowAutoLogin && await _tryAutoLogin()) {
          return _downloadFromServer(
            syncTimeForDownload,
            allowAutoLogin: false,
          );
        }
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _setLastSyncError(_serverErrorMessage('下载同步', response));
        return (success: false, tokenExpired: false, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['tables'] != null) {
        await AppDatabase.applySyncChanges(data['tables']);
      } else {
        _setLastSyncError('下载同步失败: 服务器响应缺少 tables');
        return (success: false, tokenExpired: false, serverLastSync: null);
      }

      return (
        success: true,
        tokenExpired: false,
        serverLastSync: data['serverLastSync'] as int?,
      );
    } catch (e) {
      _setLastSyncError(_friendlyRequestError(e, '下载同步'));
      return (success: false, tokenExpired: null, serverLastSync: null);
    }
  }

  /// 后台触发同步（fire-and-forget，不阻塞调用方）
  static void triggerBackgroundSync({
    Duration debounce = const Duration(seconds: 2),
  }) {
    if (!isLoggedIn) return;
    _syncRequested = true;
    _scheduleQueuedSync(debounce);
  }

  static void _scheduleQueuedSync(Duration debounce) {
    _debouncedSyncTimer?.cancel();
    _debouncedSyncTimer = Timer(debounce, () {
      unawaited(_drainBackgroundSyncQueue());
    });
  }

  static Future<void> _drainBackgroundSyncQueue() async {
    if (!isLoggedIn || _syncing || !_syncRequested) return;
    _syncRequested = false;
    await fullSync().catchError((_) => (success: false, tokenExpired: false));
  }

  /// 启动定时同步，每隔 [interval] 自动执行一次后台同步
  static void startAutoSync({Duration interval = const Duration(minutes: 5)}) {
    _autoSyncTimer?.cancel();
    if (isLoggedIn) {
      // 登录或应用启动后立即收敛本机迁移/离线变更，后续仍按固定间隔检查。
      triggerBackgroundSync(debounce: Duration.zero);
    }
    _autoSyncTimer = Timer.periodic(interval, (_) {
      triggerBackgroundSync();
    });
  }

  /// 停止定时同步
  static void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _debouncedSyncTimer?.cancel();
    _debouncedSyncTimer = null;
    _syncRequested = false;
  }
}
