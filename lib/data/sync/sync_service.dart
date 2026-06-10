import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/database/app_database.dart';

class SyncService {
  // 默认服务器地址
  static const _defaultServerUrl = 'http://1.12.46.222:6677';

  // 内存中缓存的同步配置和凭证
  static String _serverUrl = _defaultServerUrl;
  static String _token = '';
  static String _userId = '';
  static String _username = '';
  static String _fakePassword = ''; // 用于在 UI 中显示的虚拟密码
  static String _realPassword = ''; // 真实的密码明文缓存
  static int _lastSyncTime = 0;
  static bool _syncing = false; // 防止并发同步
  static bool _syncRequested = false; // 同步过程中如有新请求，结束后补跑一次
  static Timer? _debouncedSyncTimer;
  static Timer? _autoSyncTimer;
  static final Set<FutureOr<void> Function()> _syncCompletedListeners = {};

  static const String _encryptionKey = 'FocusMyTimeSecretKey!';

  static String _encrypt(String text) {
    if (text.isEmpty) return '';
    final bytes = utf8.encode(text);
    final keyBytes = utf8.encode(_encryptionKey);
    final encrypted = List<int>.generate(
        bytes.length, (i) => bytes[i] ^ keyBytes[i % keyBytes.length]);
    return base64.encode(encrypted);
  }

  static String _decrypt(String base64text) {
    if (base64text.isEmpty) return '';
    try {
      final bytes = base64.decode(base64text);
      final keyBytes = utf8.encode(_encryptionKey);
      final decrypted = List<int>.generate(
          bytes.length, (i) => bytes[i] ^ keyBytes[i % keyBytes.length]);
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
    if (serverUrl != null) _serverUrl = serverUrl;

    final token = await AppDatabase.getSetting('syncToken');
    if (token != null) _token = token;

    final userId = await AppDatabase.getSetting('syncUserId');
    if (userId != null) _userId = userId;

    // 加载保存的用户名和虚拟密码，用于在重启后保持 UI 状态
    final username = await AppDatabase.getSetting('syncUsername');
    if (username != null) _username = username;

    final fakePassword = await AppDatabase.getSetting('syncFakePassword');
    if (fakePassword != null) _fakePassword = fakePassword;

    final realPasswordEncrypted =
        await AppDatabase.getSetting('syncRealPassword');
    if (realPasswordEncrypted != null) {
      _realPassword = _decrypt(realPasswordEncrypted);
    }

    final lastSync = await AppDatabase.getSetting('lastSyncTime');
    if (lastSync != null) _lastSyncTime = int.tryParse(lastSync) ?? 0;

    // 数据恢复检测：如果 DB 被意外清空但 lastSyncTime 非零，
    // 重置为 0 以触发全量同步从服务器恢复数据
    await _recoverIfDataLost();
  }

  /// 检测到数据库被清空时自动重置 lastSyncTime，确保下次同步从服务器全量拉取
  static Future<void> _recoverIfDataLost() async {
    if (_lastSyncTime == 0) return;
    try {
      final db = await AppDatabase.database;
      final result = await db
          .rawQuery('SELECT COUNT(*) as cnt FROM tasks WHERE deleted = 0');
      final taskCount = (result.first['cnt'] as int?) ?? 0;
      if (taskCount == 0) {
        _lastSyncTime = 0;
        await AppDatabase.setSetting('lastSyncTime', '0');
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

  static void addSyncCompletedListener(FutureOr<void> Function() listener) {
    _syncCompletedListeners.add(listener);
  }

  static void removeSyncCompletedListener(FutureOr<void> Function() listener) {
    _syncCompletedListeners.remove(listener);
  }

  static Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    await AppDatabase.setSetting('syncServerUrl', url);
  }

  static Future<void> _saveToken(String token, String userId,
      {String? username, String? password}) async {
    _token = token;
    _userId = userId;
    await AppDatabase.setSetting('syncToken', token);
    await AppDatabase.setSetting('syncUserId', userId);

    // 如果提供了用户名，说明是登录或注册成功，保存用户名和虚拟密码
    if (username != null) {
      _username = username;
      _fakePassword = '••••••••'; // 使用固定掩码字符
      await AppDatabase.setSetting('syncUsername', _username);
      await AppDatabase.setSetting('syncFakePassword', _fakePassword);
    }

    // 如果提供了密码，说明是登录或注册成功，保存真实密码的加密版本
    if (password != null) {
      _realPassword = password;
      final encrypted = _encrypt(password);
      await AppDatabase.setSetting('syncRealPassword', encrypted);
    }
  }

  static Future<void> _clearToken() async {
    _token = '';
    _userId = '';
    _username = '';
    _fakePassword = '';
    _realPassword = '';
    await AppDatabase.setSetting('syncToken', '');
    await AppDatabase.setSetting('syncUserId', '');
    await AppDatabase.setSetting('syncUsername', '');
    await AppDatabase.setSetting('syncFakePassword', '');
    await AppDatabase.setSetting('syncRealPassword', '');
  }

  static Future<
          ({bool success, bool tokenExpired, String? error, String? userId})>
      register({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final token = data['token'] as String;
        final userId = data['userId'] as String;
        // 注册成功，保存登录凭证和用户信息
        await _saveToken(token, userId, username: username, password: password);
        return (
          success: true,
          tokenExpired: false,
          error: null,
          userId: userId
        );
      }
      return (
        success: false,
        tokenExpired: false,
        error: (data['error'] as String?) ?? '注册失败',
        userId: null
      );
    } catch (e) {
      return (
        success: false,
        tokenExpired: false,
        error: e.toString(),
        userId: null
      );
    }
  }

  static Future<
          ({bool success, bool tokenExpired, String? error, String? userId})>
      login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final token = data['token'] as String;
        final userId = data['userId'] as String;
        // 登录成功，保存登录凭证和用户信息
        await _saveToken(token, userId, username: username, password: password);
        return (
          success: true,
          tokenExpired: false,
          error: null,
          userId: userId
        );
      }
      return (
        success: false,
        tokenExpired: false,
        error: (data['error'] as String?) ?? '登录失败',
        userId: null
      );
    } catch (e) {
      return (
        success: false,
        tokenExpired: false,
        error: e.toString(),
        userId: null
      );
    }
  }

  /// 登出：清除内存中的凭证并重置本地存储
  static Future<void> logout() async {
    await _clearToken();
  }

  /// 检查当前是否已登录（通过判断是否有 Token）
  static bool get isLoggedIn => _token.isNotEmpty;

  /// 更新本地记录的上次同步时间
  static Future<void> updateLastSyncTime() async {
    _lastSyncTime = DateTime.now().millisecondsSinceEpoch;
    await AppDatabase.setSetting('lastSyncTime', _lastSyncTime.toString());
  }

  /// 执行完整同步流程：上传本地变更 -> 下载远程变更
  static Future<({bool success, bool tokenExpired})> fullSync({
    bool notifyListeners = true,
  }) async {
    if (!isLoggedIn || _syncing) {
      if (isLoggedIn && _syncing) {
        _syncRequested = true;
      }
      return (success: false, tokenExpired: false);
    }
    _syncing = true;
    try {
      // Upload local changes
      final uploadResult = await _syncToServer();
      if (!uploadResult.success) {
        return (
          success: false,
          tokenExpired: uploadResult.tokenExpired ?? false
        );
      }

      // Download remote changes（使用 _lastSyncTime 而非 serverLastSync，
      // 确保当本地 _lastSyncTime 很旧时能拉取到全部历史数据）
      final downloadResult = await _downloadFromServer(_lastSyncTime);
      if (!downloadResult.success) {
        return (
          success: false,
          tokenExpired: downloadResult.tokenExpired ?? false
        );
      }

      await updateLastSyncTime();
      if (notifyListeners) {
        await _notifySyncCompleted();
      }
      return (success: true, tokenExpired: false);
    } finally {
      _syncing = false;
      if (_syncRequested) {
        _scheduleQueuedSync(Duration.zero);
      }
    }
  }

  static Future<void> _notifySyncCompleted() async {
    for (final listener
        in List<FutureOr<void> Function()>.from(_syncCompletedListeners)) {
      await Future.sync(listener);
    }
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})>
      _syncToServer() async {
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
              'lastSyncTime': _lastSyncTime,
              'tables': payload,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) {
        await logout();
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true || data['serverLastSync'] != null) {
        return (
          success: true,
          tokenExpired: false,
          serverLastSync: data['serverLastSync'] as int?
        );
      }
      return (success: false, tokenExpired: false, serverLastSync: null);
    } catch (e) {
      return (success: false, tokenExpired: null, serverLastSync: null);
    }
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})>
      _downloadFromServer(int syncTimeForDownload) async {
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
        await logout();
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['tables'] != null) {
        await AppDatabase.applySyncChanges(data['tables']);
      }

      return (
        success: true,
        tokenExpired: false,
        serverLastSync: data['serverLastSync'] as int?
      );
    } catch (e) {
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
