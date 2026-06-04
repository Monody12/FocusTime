import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_my_time/core/utils/app_time.dart';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String htmlUrl;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.htmlUrl,
  });
}

class UpdateService {
  static const String _lastCheckKey = 'last_update_check_date';
  static const String _ignoredVersionKey = 'ignored_update_version';
  static const String _repoUrl =
      'https://api.github.com/repos/Monody12/FocusTime/releases/latest';

  /// 检查是否有更新
  /// 每天最多检查一次，或者如果有忽略的版本则跳过该版本
  static Future<UpdateInfo?> checkForUpdates({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查今天是否已经检查过
      final lastCheckStr = prefs.getString(_lastCheckKey);
      final todayStr = AppTime.formatDate(AppTime.now());

      if (!force && lastCheckStr == todayStr) {
        return null; // 今天已经检查过了
      }

      // 调用 API
      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode != 200) {
        return null; // 请求失败
      }

      final data = json.decode(response.body);
      final tagName = data['tag_name'] as String; // e.g. v1.0.11
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;

      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 对比版本
      if (_isNewerVersion(latestVersion, currentVersion)) {
        // 检查是否是被忽略的版本
        final ignoredVersion = prefs.getString(_ignoredVersionKey);
        if (!force && ignoredVersion == latestVersion) {
          return null;
        }

        // 记录今天的检查时间
        await prefs.setString(_lastCheckKey, todayStr);

        return UpdateInfo(
          version: latestVersion,
          releaseNotes: data['body'] ?? '暂无更新说明',
          htmlUrl: data['html_url'] ??
              'https://github.com/Monody12/FocusTime/releases/latest',
        );
      }

      // 如果没有更新，也记录今天检查过了
      await prefs.setString(_lastCheckKey, todayStr);
      return null;
    } catch (e) {
      // 忽略检查更新的错误
      return null;
    }
  }

  /// 忽略某个版本
  static Future<void> ignoreVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ignoredVersionKey, version);
  }

  /// 比较版本号 (例如 1.0.11 > 1.0.10)
  static bool _isNewerVersion(String latest, String current) {
    final latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    return latestParts.length > currentParts.length;
  }
}
