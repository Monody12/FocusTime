// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web 平台：把运行期异常写入 localStorage，便于自部署排障时在
/// 浏览器控制台/自动化脚本中读取。
void reportDebugError(String message) {
  try {
    final log = html.window.localStorage['flutter_error_log'] ?? '';
    final entry = '${DateTime.now().toIso8601String()} $message';
    html.window.localStorage['flutter_error_log'] =
        (log.isEmpty ? entry : '$log\n$entry').length > 8000
        ? (log.split('\n').skip(5).toList()..add(entry)).join('\n')
        : '$log\n$entry'.trim();
  } catch (_) {}
}
