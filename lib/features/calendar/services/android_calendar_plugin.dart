import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/services.dart';

/// Android 日历事件写入封装。
///
/// 避开 device_calendar 在更新事件时“删除旧 Reminders 再插入”的流程。
/// Android 16 / 部分 OEM 日历 Provider 可能拒绝删除提醒子记录，导致更新失败后
/// 上层新建事件，最终留下旧提醒。这里改为 UPDATE Event，并对 Reminder 做
/// update/insert 的 best-effort 操作。
class AndroidCalendarPlugin {
  static const MethodChannel _channel =
      MethodChannel('com.focusmytime.android_calendar');

  Future<Result<String>> createOrUpdateEvent(Event event) async {
    final result = Result<String>();
    try {
      final eventId = await _channel.invokeMethod<String>(
        'createOrUpdateEvent',
        {
          'calendarId': event.calendarId,
          'eventId': event.eventId,
          'title': event.title,
          'description': event.description,
          'start': event.start?.millisecondsSinceEpoch,
          'end': event.end?.millisecondsSinceEpoch,
          'status': event.status == null || event.status == EventStatus.None
              ? null
              : event.status!.name,
          'reminders':
              event.reminders?.map((reminder) => reminder.minutes).toList() ??
                  <int>[],
        },
      );
      result.data = eventId;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }

  Future<Result<bool>> deleteEvent(String? calendarId, String eventId) async {
    final result = Result<bool>();
    try {
      final deleted = await _channel.invokeMethod<bool>(
        'deleteEvent',
        {
          'calendarId': calendarId,
          'eventId': eventId,
        },
      );
      result.data = deleted == true;
    } catch (e) {
      result.errors.add(ResultError(0, e.toString()));
    }
    return result;
  }
}
