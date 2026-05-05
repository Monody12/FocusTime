import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:focus_timer/data/database/app_database.dart';

class SyncService {
  static const _defaultServerUrl = 'http://1.12.46.222:6677';

  static String _serverUrl = _defaultServerUrl;
  static String _token = '';
  static String _userId = '';
  static int _lastSyncTime = 0;

  static Future<void> init() async {
    // 从本地数据库加载同步配置
    final serverUrl = await AppDatabase.getSetting('syncServerUrl');
    if (serverUrl != null) _serverUrl = serverUrl;

    final token = await AppDatabase.getSetting('syncToken');
    if (token != null) _token = token;

    final userId = await AppDatabase.getSetting('syncUserId');
    if (userId != null) _userId = userId;

    final lastSync = await AppDatabase.getSetting('lastSyncTime');
    if (lastSync != null) _lastSyncTime = int.tryParse(lastSync) ?? 0;
  }

  static String get serverUrl => _serverUrl;
  static String get token => _token;
  static String get userId => _userId;
  static int get lastSyncTime => _lastSyncTime;

  static Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    await AppDatabase.setSetting('syncServerUrl', url);
  }

  static Future<void> _saveToken(String token, String userId) async {
    _token = token;
    _userId = userId;
    await AppDatabase.setSetting('syncToken', token);
    await AppDatabase.setSetting('syncUserId', userId);
  }

  static Future<void> _clearToken() async {
    _token = '';
    _userId = '';
    await AppDatabase.setSetting('syncToken', '');
    await AppDatabase.setSetting('syncUserId', '');
  }

  static Future<({bool success, bool tokenExpired, String? error, String? userId})> register({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final token = data['token'] as String;
        final userId = data['userId'] as String;
        await _saveToken(token, userId);
        return (success: true, tokenExpired: false, error: null, userId: userId);
      }
      return (success: false, tokenExpired: false, error: (data['error'] as String?) ?? '注册失败', userId: null);
    } catch (e) {
      return (success: false, tokenExpired: false, error: e.toString(), userId: null);
    }
  }

  static Future<({bool success, bool tokenExpired, String? error, String? userId})> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final token = data['token'] as String;
        final userId = data['userId'] as String;
        await _saveToken(token, userId);
        return (success: true, tokenExpired: false, error: null, userId: userId);
      }
      return (success: false, tokenExpired: false, error: (data['error'] as String?) ?? '登录失败', userId: null);
    } catch (e) {
      return (success: false, tokenExpired: false, error: e.toString(), userId: null);
    }
  }

  static Future<void> logout() async {
    await _clearToken();
  }

  static bool get isLoggedIn => _token.isNotEmpty;

  static Future<void> updateLastSyncTime() async {
    _lastSyncTime = DateTime.now().millisecondsSinceEpoch;
    await AppDatabase.setSetting('lastSyncTime', _lastSyncTime.toString());
  }

  static Future<({bool success, bool tokenExpired})> fullSync() async {
    if (!isLoggedIn) {
      return (success: false, tokenExpired: false);
    }

    // Upload local changes
    final uploadResult = await _syncToServer();
    if (!uploadResult.success) {
      return (success: false, tokenExpired: uploadResult.tokenExpired ?? false);
    }

    // Download remote changes
    final downloadResult = await _downloadFromServer();
    if (!downloadResult.success) {
      return (success: false, tokenExpired: downloadResult.tokenExpired ?? false);
    }

    await updateLastSyncTime();
    return (success: true, tokenExpired: false);
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})> _syncToServer() async {
    try {
      final payload = await AppDatabase.getSyncPayload(_lastSyncTime);
      
      final response = await http.post(
        Uri.parse('$_serverUrl/api/sync'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'lastSyncTime': _lastSyncTime,
          'tables': payload,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) {
        await logout();
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true || data['serverLastSync'] != null) {
        return (success: true, tokenExpired: false, serverLastSync: data['serverLastSync'] as int?);
      }
      return (success: false, tokenExpired: false, serverLastSync: null);
    } catch (e) {
      return (success: false, tokenExpired: null, serverLastSync: null);
    }
  }

  static Future<({bool success, bool? tokenExpired, int? serverLastSync})> _downloadFromServer() async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/sync'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'lastSyncTime': _lastSyncTime,
          'tables': {
            'lists': [],
            'tasks': [],
            'sessions': [],
            'task_recurrence_completions': [],
            'settings': [],
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        await logout();
        return (success: false, tokenExpired: true, serverLastSync: null);
      }

      final data = jsonDecode(response.body);
      if (data['tables'] != null) {
        await AppDatabase.applySyncChanges(data['tables']);
      }
      
      return (success: true, tokenExpired: false, serverLastSync: data['serverLastSync'] as int?);
    } catch (e) {
      return (success: false, tokenExpired: null, serverLastSync: null);
    }
  }

  /// 启动定时同步
  static void startAutoSync() {
    // 这里可以实现定时器逻辑，或者在生命周期回调中调用
  }
}