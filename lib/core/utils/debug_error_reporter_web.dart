// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

const String _errorKey = 'flutter_error_log';
const String _logKey = 'flutter_debug_log';
const int _maxEntries = 120;

/// 调试构建（--dart-define=DEBUG_BREADCRUMBS=true）会把面包屑同时 POST 到
/// 同步服务器收集；正式构建不发送。
const bool _kRemoteDebug = bool.fromEnvironment('DEBUG_BREADCRUMBS');

final List<String> _pendingRemote = <String>[];
Timer? _remoteFlushTimer;

void _append(String key, String entry) {
  try {
    final existing = html.window.localStorage[key] ?? '';
    final merged = existing.isEmpty ? entry : '$existing\n$entry';
    if (merged.length > 8000) {
      final lines = merged.split('\n');
      html.window.localStorage[key] = lines
          .sublist(lines.length > _maxEntries ? lines.length - _maxEntries : 0)
          .join('\n');
    } else {
      html.window.localStorage[key] = merged;
    }
  } catch (_) {}
}

void _queueRemote(String entry) {
  if (!_kRemoteDebug) return;
  _pendingRemote.add(entry);
  _remoteFlushTimer ??= Timer(const Duration(seconds: 3), _flushRemote);
}

void _flushRemote() {
  _remoteFlushTimer = null;
  if (_pendingRemote.isEmpty) return;
  final batch = List<String>.from(_pendingRemote);
  _pendingRemote.clear();
  try {
    final origin = html.window.location.origin;
    html.HttpRequest.request(
      '$origin/api/debug/breadcrumb',
      method: 'POST',
      requestHeaders: {'Content-Type': 'application/json'},
      sendData: jsonEncode({'entries': batch}),
    ).catchError((_) => html.HttpRequest());
  } catch (_) {}
}

String _stamp() {
  try {
    return DateTime.now().toIso8601String().substring(11, 23);
  } catch (_) {
    return '';
  }
}

/// 把运行期异常写入 localStorage；调试构建同时上报服务器。
void reportDebugError(String message) {
  try {
    final entry = '${_stamp()} ERROR: $message';
    _append(_errorKey, entry);
    _queueRemote(entry);
  } catch (_) {}
}

/// 调试面包屑：关键生命周期节点的轻量日志（环形缓冲）。
void debugLog(String tag, String message) {
  try {
    final entry = '${_stamp()} [$tag] $message';
    _append(_logKey, entry);
    _queueRemote(entry);
  } catch (_) {}
}
