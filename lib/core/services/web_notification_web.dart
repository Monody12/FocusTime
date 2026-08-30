import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> showWebNotification(String title, String body) async {
  try {
    var permission = web.Notification.permission;
    if (permission == 'default') {
      permission = (await web.Notification.requestPermission().toDart).toDart;
    }
    if (permission != 'granted') return false;
    web.Notification(
      title,
      web.NotificationOptions(body: body, tag: 'focus-task-reminder'),
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> requestWebNotificationPermission() async {
  try {
    final current = web.Notification.permission;
    if (current == 'granted') return true;
    if (current == 'denied') return false;
    final permission =
        (await web.Notification.requestPermission().toDart).toDart;
    return permission == 'granted';
  } catch (_) {
    return false;
  }
}
