import 'package:flutter/services.dart';
import 'package:device_calendar/device_calendar.dart';

/// macOS 日历操作插件封装
///
/// `device_calendar` 不提供 macOS 实现，此类通过 FlutterMethodChannel
/// ("com.focusmytime.calendar") 桥接原生 EventKit API，
/// 对外暴露与 `DeviceCalendarPlugin` 相同的 Result<T> 接口风格，
/// 使 `CalendarService` 可以用统一的方式调用 Android 和 macOS 日历功能。
class MacOsCalendarPlugin {
  /// 与 MainFlutterWindow.swift 中注册的 channel 名称一致
  static const MethodChannel _channel = MethodChannel('com.focusmytime.calendar');

  /// 检查当前应用是否已获得 macOS 日历访问权限
  Future<Result<bool>> hasPermissions() async {
    final result = Result<bool>();
    try {
      final bool hasPerm = await _channel.invokeMethod('hasPermissions');
      result.data = hasPerm;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 请求 macOS 日历访问权限
  /// macOS 14+ 走 fullAccess API，macOS 10.15~13 走旧版 requestAccess
  Future<Result<bool>> requestPermissions() async {
    final result = Result<bool>();
    try {
      final bool hasPerm = await _channel.invokeMethod('requestPermissions');
      result.data = hasPerm;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 获取设备上所有日历列表
  Future<Result<List<Calendar>>> retrieveCalendars() async {
    final result = Result<List<Calendar>>();
    try {
      final List<dynamic> calendarsList = await _channel.invokeMethod('retrieveCalendars');
      final List<Calendar> calendars = calendarsList.map((c) {
        final map = Map<String, dynamic>.from(c);
        return Calendar(
          id: map['id'] as String,
          name: map['name'] as String,
          isReadOnly: map['isReadOnly'] as bool? ?? false,
          accountName: 'FocusMyTime',
        );
      }).toList();
      result.data = calendars;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 创建新日历，返回创建后的日历 ID
  /// macOS 端创建时会自动选择本地 (Local) 日历源
  Future<Result<String>> createCalendar(
    String calendarName, {
    Color? calendarColor,
    String? localAccountName,
  }) async {
    final result = Result<String>();
    try {
      final String calendarId = await _channel.invokeMethod('createCalendar', {
        'name': calendarName,
      });
      result.data = calendarId;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 创建或更新日历事件
  /// 有 eventId → 更新已有事件，无 eventId → 创建新事件
  /// 返回保存后的事件 ID
  Future<Result<String>> createOrUpdateEvent(Event event) async {
    final result = Result<String>();
    try {
      final String eventId = await _channel.invokeMethod('createOrUpdateEvent', {
        'calendarId': event.calendarId,
        'eventId': event.eventId,
        'title': event.title,
        'description': event.description,
        'start': event.start?.millisecondsSinceEpoch,
        'end': event.end?.millisecondsSinceEpoch,
      });
      result.data = eventId;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 删除指定日历事件，事件不存在时视为成功
  Future<Result<bool>> deleteEvent(String? calendarId, String eventId) async {
    final result = Result<bool>();
    try {
      await _channel.invokeMethod('deleteEvent', {
        'calendarId': calendarId,
        'eventId': eventId,
      });
      result.data = true;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  /// 删除整个日历及其所有事件
  Future<Result<bool>> deleteCalendar(String calendarId) async {
    final result = Result<bool>();
    try {
      await _channel.invokeMethod('deleteCalendar', {
        'calendarId': calendarId,
      });
      result.data = true;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }
}
