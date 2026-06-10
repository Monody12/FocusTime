import 'dart:io';
import 'dart:developer' as dev;
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/calendar/services/macos_calendar_plugin.dart';

/// 系统日历同步服务
class CalendarService {
  static final DeviceCalendarPlugin _deviceCalendarPlugin =
      DeviceCalendarPlugin();
  static final MacOsCalendarPlugin _macOsCalendarPlugin = MacOsCalendarPlugin();

  static String? _calendarId;
  static const String _calendarName = 'FocusMyTime 提醒';
  static const String _prefKeyEnabled = 'calendar_sync_enabled';
  static Future<bool>? _initFuture;

  /// 检查是否启用了日历同步
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyEnabled) ?? false;
  }

  /// 设置是否启用日历同步
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, enabled);
  }

  /// 检查是否有日历权限（非移动平台直接返回 false）
  static Future<bool> hasPermissions() async {
    if (Platform.isWindows || Platform.isLinux) return false;
    try {
      final permissions = await _hasPermissionsResult();
      return permissions.isSuccess && permissions.data == true;
    } catch (e) {
      dev.log('[CalendarService] 权限检查异常: $e');
      return false;
    }
  }

  static Future<Result<bool>> _hasPermissionsResult() {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.hasPermissions()
        : _deviceCalendarPlugin.hasPermissions();
  }

  static Future<Result<bool>> _requestPermissions() {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.requestPermissions()
        : _deviceCalendarPlugin.requestPermissions();
  }

  static Future<Result<List<Calendar>>> _retrieveCalendars() {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.retrieveCalendars()
        : _deviceCalendarPlugin.retrieveCalendars();
  }

  static Future<Result<String>> _createCalendar(String name) {
    if (Platform.isMacOS) {
      return _macOsCalendarPlugin.createCalendar(name);
    }

    return _deviceCalendarPlugin.createCalendar(
      name,
      calendarColor: AppTheme.defaultScheme.light.accent,
      localAccountName: 'FocusMyTime',
    );
  }

  static Future<Result<String>?> _createOrUpdateEvent(Event event) {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.createOrUpdateEvent(event)
        : _deviceCalendarPlugin.createOrUpdateEvent(event);
  }

  static Future<Result<bool>> _deleteEvent(String? calendarId, String eventId) {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.deleteEvent(calendarId, eventId)
        : _deviceCalendarPlugin.deleteEvent(calendarId, eventId);
  }

  static Future<Result<bool>> _deleteCalendar(String calendarId) {
    return Platform.isMacOS
        ? _macOsCalendarPlugin.deleteCalendar(calendarId)
        : _deviceCalendarPlugin.deleteCalendar(calendarId);
  }

  /// 初始化并获取/创建专用日历（带并发锁）
  static Future<bool> _ensureCalendar() async {
    if (Platform.isWindows || Platform.isLinux) return false;
    if (_calendarId != null) return true;
    if (_initFuture != null) return _initFuture!;

    _initFuture = _doEnsureCalendar();
    final result = await _initFuture!;
    _initFuture = null;
    return result;
  }

  static Future<bool> _doEnsureCalendar() async {
    final permissions = await _hasPermissionsResult();
    if (permissions.isSuccess && !permissions.data!) {
      final request = await _requestPermissions();
      if (!request.isSuccess || !request.data!) {
        dev.log('[CalendarService] 权限请求失败');
        return false;
      }
    }

    final calendars = await _retrieveCalendars();
    if (calendars.isSuccess && calendars.data != null) {
      final existing =
          calendars.data!.where((c) => c.name == _calendarName).firstOrNull;
      if (existing != null) {
        _calendarId = existing.id;
        dev.log('[CalendarService] 复用已有日历: $_calendarName (ID: $_calendarId)');
        return true;
      }
    }

    // 创建专用日历，便于后续安全清理和重建。
    if (Platform.isAndroid || Platform.isMacOS) {
      final createResult = await _createCalendar(_calendarName);
      if (createResult.isSuccess && createResult.data != null) {
        _calendarId = createResult.data;
        dev.log('[CalendarService] 创建新日历成功: $_calendarName (ID: $_calendarId)');
        return true;
      }
      dev.log('[CalendarService] 创建新日历失败，尝试回退');
    }

    // 回退方案：使用第一个可写的日历
    if (calendars.isSuccess && calendars.data != null) {
      final writable =
          calendars.data!.where((c) => !(c.isReadOnly ?? false)).firstOrNull;
      if (writable != null) {
        _calendarId = writable.id;
        dev.log(
            '[CalendarService] 回退使用可写日历: ${writable.name} (ID: $_calendarId, Account: ${writable.accountName})');
        return true;
      }
    }

    dev.log('[CalendarService] 未能找到或创建可用日历');
    return false;
  }

  /// 同步单个任务到日历，返回事件 ID
  static Future<String?> syncTask(TaskItem task) async {
    if (!(await isEnabled())) return task.calendarEventId;
    if (!(await _ensureCalendar())) return task.calendarEventId;

    // 如果任务取消了提醒，从日历移除
    if (task.reminderAt == null) {
      if (task.calendarEventId != null) {
        await removeTask(task.calendarEventId!);
      }
      return null;
    }

    final startTime = AppTime.fromMillisecondsSinceEpoch(task.reminderAt!);
    // 如果提醒时间是过去，且还没有同步过，则不创建
    if (startTime.isBefore(DateTime.now()) && task.calendarEventId == null) {
      return null;
    }

    // 传入已有 eventId 让插件执行 UPDATE 而非 DELETE+INSERT，
    // 避免 Android 14+ 上 deleteEvent 权限受限导致重复日程
    final event = Event(
      _calendarId,
      eventId: task.calendarEventId,
      title: '任务提醒: ${task.title}',
      description: task.notes ?? '来自 FocusMyTime 的任务提醒',
      start: tz.TZDateTime.from(startTime, AppTime.notificationLocation()),
      end: tz.TZDateTime.from(startTime.add(const Duration(minutes: 15)),
          AppTime.notificationLocation()),
      reminders: task.completed ? [] : [Reminder(minutes: 0)],
    );

    final result = await _createOrUpdateEvent(event);
    if (result != null && result.isSuccess && result.data != null) {
      dev.log(
          '[CalendarService] 已同步任务到日历: ${task.title}, EventID: ${result.data}');
      return result.data;
    }

    dev.log(
        '[CalendarService] createOrUpdateEvent 失败，尝试回退方案: ${result?.errors.map((e) => e.errorMessage).join(', ') ?? 'unknown'}');
    // 如果 UPDATE 失败（如事件被手动删除），回退到 DELETE+CREATE
    if (task.calendarEventId != null) {
      await _deleteEvent(_calendarId, task.calendarEventId!);
    }
    final newEvent = Event(
      _calendarId,
      title: '任务提醒: ${task.title}',
      description: task.notes ?? '来自 FocusMyTime 的任务提醒',
      start: tz.TZDateTime.from(startTime, AppTime.notificationLocation()),
      end: tz.TZDateTime.from(startTime.add(const Duration(minutes: 15)),
          AppTime.notificationLocation()),
      reminders: task.completed ? [] : [Reminder(minutes: 0)],
    );
    final retryResult = await _createOrUpdateEvent(newEvent);
    if (retryResult != null &&
        retryResult.isSuccess &&
        retryResult.data != null) {
      dev.log(
          '[CalendarService] 重建成功: ${task.title}, EventID: ${retryResult.data}');
      return retryResult.data;
    }

    dev.log('[CalendarService] 同步日历完全失败，保留旧 eventId');
    return task.calendarEventId;
  }

  /// 从日历移除任务提醒
  static Future<void> removeTask(String eventId) async {
    if (!(await _ensureCalendar())) return;
    final result = await _deleteEvent(_calendarId, eventId);
    if (result.isSuccess) {
      dev.log('[CalendarService] 已从日历移除事件: $eventId');
      return;
    }
    // Android 14+ 可能阻止删除，降级为将事件标记为已取消
    dev.log('[CalendarService] 删除事件失败，尝试标记为已取消: $eventId');
    try {
      final cancelEvent = Event(
        _calendarId,
        eventId: eventId,
        title: '（已取消）',
        start: tz.TZDateTime.now(tz.local),
        end: tz.TZDateTime.now(tz.local),
        status: EventStatus.Canceled,
        reminders: [],
      );
      final updateResult = await _createOrUpdateEvent(cancelEvent);
      if (updateResult != null && updateResult.isSuccess) {
        dev.log('[CalendarService] 已将事件标记为取消: $eventId');
      } else {
        dev.log(
            '[CalendarService] 标记取消也失败: ${updateResult?.errors.map((e) => e.errorMessage).join(', ')}');
      }
    } catch (e) {
      dev.log('[CalendarService] 删除回退方案异常: $e');
    }
  }

  /// 强制清理并重建整个日历系统
  static Future<void> forceRebuildCalendar(List<TaskItem> tasks) async {
    final permissions = await _hasPermissionsResult();
    if (!permissions.isSuccess || !permissions.data!) {
      final request = await _requestPermissions();
      if (!request.isSuccess || !request.data!) return;
    }

    // 1. 找到所有同名日历并全部删除
    final calendars = await _retrieveCalendars();
    if (calendars.isSuccess && calendars.data != null) {
      for (final c in calendars.data!) {
        if (c.name == _calendarName && c.id != null) {
          try {
            await _deleteCalendar(c.id!);
          } catch (e) {
            dev.log('[CalendarService] 删除旧日历失败: ${e.toString()}');
          }
        }
      }
    }

    // 2. 重置内存状态
    _calendarId = null;

    // 3. 强制清空数据库中所有任务的 eventID，同时更新 updated_at 触发同步
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final db = await AppDatabase.database;
    await db.execute(
        'UPDATE tasks SET calendar_event_id = NULL, updated_at = ?', [nowMs]);

    // 4. 重新初始化一个纯净的日历
    await _ensureCalendar();

    // 5. 将当前所有有效任务重新写入日历
    for (final task in tasks) {
      if (task.reminderAt != null && !task.completed) {
        // 创建一个没有 ID 的副本以强制新建
        final newTask =
            task.copyWith(calendarEventId: null, clearReminder: false);
        final eventId = await syncTask(newTask);
        if (eventId != null) {
          await AppDatabase.updateTask(task.id, {'calendarEventId': eventId});
        }
      }
    }

    dev.log('[CalendarService] 强制清理与重建完成！');
  }

  static bool _refreshInProgress = false;

  /// 全量刷新（已弃用，建议使用统一调度）
  static Future<void> refreshAll(List<TaskItem> tasks) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    try {
      if (!(await isEnabled())) return;
      for (final task in tasks) {
        await syncTask(task);
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  /// 触发一次立即的日历同步测试
  static Future<bool> triggerTestSync() async {
    if (!(await _ensureCalendar())) return false;

    final startTime = AppTime.now().add(const Duration(minutes: 5));
    final event = Event(
      _calendarId,
      title: 'FocusMyTime 同步测试',
      description: '如果你看到这个事件，说明日历同步功能正常。',
      start: tz.TZDateTime.from(startTime, AppTime.notificationLocation()),
      end: tz.TZDateTime.from(startTime.add(const Duration(minutes: 15)),
          AppTime.notificationLocation()),
      reminders: [
        Reminder(minutes: 0), // 事件开始时提醒
      ],
    );

    final result = await _createOrUpdateEvent(event);
    return result?.isSuccess ?? false;
  }
}
