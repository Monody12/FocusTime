// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const String _errorKey = 'flutter_error_log';
const String _logKey = 'flutter_debug_log';
const int _maxEntries = 120;

void _append(String key, String entry, {bool compact = false}) {
  try {
    final existing = html.window.localStorage[key] ?? '';
    final merged = existing.isEmpty ? entry : '$existing\n$entry';
    if (merged.length > 8000) {
      final lines = merged.split('\n');
      html.window.localStorage[key] =
          lines.sublist(lines.length > _maxEntries ? lines.length - _maxEntries : 0).join('\n');
    } else {
      html.window.localStorage[key] = merged;
    }
  } catch (_) {}
}

/// 把运行期异常写入 localStorage，便于自部署排障时读取。
void reportDebugError(String message) {
  try {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _append(_errorKey, '$ts ERROR: $message', compact: true);
  } catch (_) {}
}

/// 调试面包屑：关键生命周期节点的轻量日志（环形缓冲）。
void debugLog(String tag, String message) {
  try {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _append(_logKey, '$ts [$tag] $message');
  } catch (_) {}
}
