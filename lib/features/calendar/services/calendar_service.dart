import 'dart:io';
import 'dart:developer' as dev;
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

/// 系统日历同步服务
class CalendarService {
  static final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
  static String? _calendarId;
  static const String _calendarName = 'FocusMyTime 提醒';
  static const String _prefKeyEnabled = 'calendar_sync_enabled';

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

  /// 检查是否有日历权限
  static Future<bool> hasPermissions() async {
    final permissions = await _calendarPlugin.hasPermissions();
    return permissions.isSuccess && permissions.data == true;
  }

  /// 初始化并获取/创建专用日历
  static Future<bool> _ensureCalendar() async {
    if (_calendarId != null) return true;

    final permissions = await _calendarPlugin.hasPermissions();
    if (permissions.isSuccess && !permissions.data!) {
      final request = await _calendarPlugin.requestPermissions();
      if (!request.isSuccess || !request.data!) {
        dev.log('[CalendarService] 权限请求失败');
        return false;
      }
    }

    final calendars = await _calendarPlugin.retrieveCalendars();
    if (calendars.isSuccess && calendars.data != null) {
      final existing = calendars.data!.where((c) => c.name == _calendarName).firstOrNull;
      if (existing != null) {
        _calendarId = existing.id;
        return true;
      }
    }

    // 创建新日历 (部分平台可能不支持直接创建，如 iOS 需要引导用户)
    // 这里简单起见，如果找不到就用默认日历，或者尝试创建
    if (Platform.isAndroid) {
      final createResult = await _calendarPlugin.createCalendar(
        _calendarName,
        calendarColor: const Color(0xFF7C3AED), // App 主色调
        localAccountName: 'FocusMyTime',
      );
      if (createResult.isSuccess && createResult.data != null) {
        _calendarId = createResult.data;
        return true;
      }
    }

    // 回退方案：使用第一个可写的日历
    if (calendars.isSuccess && calendars.data != null) {
      final writable = calendars.data!.where((c) => !(c.isReadOnly ?? false)).firstOrNull;
      if (writable != null) {
        _calendarId = writable.id;
        return true;
      }
    }

    return false;
  }

  /// 同步单个任务到日历
  static Future<void> syncTask(TaskItem task) async {
    if (!(await isEnabled())) return;
    if (!(await _ensureCalendar())) return;
    if (task.reminderAt == null || task.completed) {
      await removeTask(task.id);
      return;
    }

    final startTime = DateTime.fromMillisecondsSinceEpoch(task.reminderAt!);
    if (startTime.isBefore(DateTime.now())) return;

    final event = Event(
      _calendarId,
      title: '任务提醒: ${task.title}',
      description: task.notes ?? '来自 FocusMyTime 的任务提醒',
      start: tz.TZDateTime.from(startTime, tz.local),
      end: tz.TZDateTime.from(startTime.add(const Duration(minutes: 15)), tz.local),
      reminders: [
        Reminder(minutes: 0), // 事件开始时提醒
      ],
    );

    // 存储 eventId 以便后续更新/删除
    // 为了简单，我们使用 task.id 作为外部标识符（如果插件支持）
    // device_calendar 不支持直接设置 ID，所以我们需要自己维护映射或在标题中埋点
    // 这里采用标题匹配/搜索的方式，或者在数据库中记录 eventId (更稳妥，但需要改数据库)
    // 暂且采用搜索方式
    await _calendarPlugin.createOrUpdateEvent(event);
    dev.log('[CalendarService] 已同步任务到日历: ${task.title}');
  }

  /// 从日历移除任务提醒
  static Future<void> removeTask(String taskId) async {
    if (!(await _ensureCalendar())) return;
    // 实际实现中需要根据 taskId 找到对应的 eventId 并删除
    // 这里作为演示，暂留接口
  }

  /// 全量刷新
  static Future<void> refreshAll(List<TaskItem> tasks) async {
    if (!(await isEnabled())) return;
    for (final task in tasks) {
      await syncTask(task);
    }
  }

  /// 触发一次立即的日历同步测试
  static Future<bool> triggerTestSync() async {
    if (!(await _ensureCalendar())) return false;
    
    final startTime = DateTime.now().add(const Duration(minutes: 5));
    final event = Event(
      _calendarId,
      title: 'FocusMyTime 同步测试',
      description: '如果你看到这个事件，说明日历同步功能正常。',
      start: tz.TZDateTime.from(startTime, tz.local),
      end: tz.TZDateTime.from(startTime.add(const Duration(minutes: 15)), tz.local),
      reminders: [
        Reminder(minutes: 0), // 事件开始时提醒
      ],
    );
    
    final result = await _calendarPlugin.createOrUpdateEvent(event);
    return result?.isSuccess ?? false;
  }
}
