import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

/// 浏览器不能直接访问操作系统日历。保留服务接口，使任务功能可独立运行。
class CalendarService {
  static Future<bool> isEnabled() async => false;

  static Future<void> setEnabled(bool enabled) async {}

  static Future<bool> hasPermissions() async => false;

  static Future<String?> syncTask(TaskItem task) async => null;

  static Future<void> removeTask(String eventId) async {}

  static Future<void> forceRebuildCalendar(List<TaskItem> tasks) async {}

  static Future<void> refreshAll(List<TaskItem> tasks) async {}

  static Future<bool> triggerTestSync() async => false;
}
