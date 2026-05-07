import 'dart:io';
import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:windows_notification/windows_notification.dart';
import 'package:windows_notification/notification_message.dart';
import '../providers/task_provider.dart';

/// 任务提醒服务
/// 职责：管理任务的定时提醒通知，支持 Android (系统级调度) 和 Windows (应用级调度)
class ReminderService {
  static final FlutterLocalNotificationsPlugin _androidPlugin = FlutterLocalNotificationsPlugin();
  static WindowsNotification? _winNotifier;
  static bool _initialized = false;
  
  // 用于追踪 Windows 端的内存定时器，以便在任务删除或提醒更改时取消它们
  static final Map<String, dynamic> _windowsTimers = {};
  
  static Function(String)? _onAction;
  
  /// 设置通知动作监听器
  static void setActionListener(Function(String) listener) {
    _onAction = listener;
  }

  /// 初始化服务，设置时区和通知通道
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // 1. 初始化时区数据 (用于 Android 调度，确保通知在本地时间准时弹出)
    tz.initializeTimeZones();
    final dynamic timeZoneValue = await FlutterTimezone.getLocalTimezone();
    // 兼容不同版本的 flutter_timezone 插件
    // 有些版本返回 String，有些返回 TimezoneInfo 对象
    String timeZoneName;
    if (timeZoneValue is String) {
      timeZoneName = timeZoneValue;
    } else {
      // 尝试获取 .name 属性，或者从 toString() 中解析出名称
      try {
        timeZoneName = (timeZoneValue as dynamic).name ?? timeZoneValue.toString();
      } catch (e) {
        timeZoneName = timeZoneValue.toString();
      }
    }
    
    // 如果 toString 包含了 "TimezoneInfo(" 前缀，则尝试提取括号内的内容
    if (timeZoneName.contains('TimezoneInfo(')) {
      final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(timeZoneName);
      if (match != null) {
        timeZoneName = match.group(1)!;
      }
    }
    
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // 2. 初始化 Android 通知
    if (Platform.isAndroid) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );
      await _androidPlugin.initialize(initializationSettings);
      
      // 创建提醒专用的通知渠道
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'task_reminders',
        '任务提醒',
        description: '用于发送定时任务提醒',
        importance: Importance.max,
      );
      await _androidPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }

    // 3. 初始化 Windows 通知客户端
    if (Platform.isWindows) {
      _winNotifier = WindowsNotification(
        applicationId: r'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',
      );
      
      _winNotifier!.initNotificationCallBack((details) {
        final String? arguments = details.argrument;
        dev.log('[ReminderService] Windows 提醒通知被激活, 动作: $arguments');
        if (arguments != null && _onAction != null) {
          _onAction!(arguments);
        }
      });
    }

    _initialized = true;
    dev.log('[ReminderService] 初始化完成, 时区: $timeZoneName');
  }

  /// 为单个任务调度提醒
  /// 如果任务已完成或没有设置提醒时间，则取消现有调度
  static Future<void> scheduleReminder(TaskItem task) async {
    if (!_initialized) await initialize();
    
    // 如果任务已完成或提醒时间为空，清理现有的调度
    if (task.reminderAt == null || task.completed) {
      await cancelReminder(task.id);
      return;
    }

    final reminderDateTime = DateTime.fromMillisecondsSinceEpoch(task.reminderAt!);
    // 如果提醒时间是过去，则不进行调度
    if (reminderDateTime.isBefore(DateTime.now())) {
      dev.log('[ReminderService] 提醒时间已过期: ${task.title}');
      return;
    }

    if (Platform.isAndroid) {
      await _scheduleAndroid(task, reminderDateTime);
    } else if (Platform.isWindows) {
      _scheduleWindows(task, reminderDateTime);
    }
  }

  /// 取消指定任务的提醒调度
  static Future<void> cancelReminder(String taskId) async {
    // Android 端：根据任务 ID 的 Hash 取消系统调度
    if (Platform.isAndroid) {
      final int notificationId = taskId.hashCode;
      await _androidPlugin.cancel(notificationId);
    }
    
    // Windows 端：取消内存中的定时器
    if (Platform.isWindows) {
      final existingTimer = _windowsTimers[taskId];
      if (existingTimer != null) {
        if (existingTimer is StreamSubscription) {
          existingTimer.cancel();
        } else if (existingTimer is Future) {
          // Future 无法直接取消，但在回调中会通过标志位检查
        }
        _windowsTimers.remove(taskId);
      }
    }
  }

  static Future<void> _scheduleAndroid(TaskItem task, DateTime scheduledTime) async {
    final int notificationId = task.id.hashCode;
    
    await _androidPlugin.zonedSchedule(
      notificationId,
      '任务提醒',
      task.title,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          '任务提醒',
          channelDescription: '用于发送定时任务提醒',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task:${task.id}',
    );
    dev.log('[ReminderService] Android 提醒已调度: ${task.title} at $scheduledTime');
  }

  static void _scheduleWindows(TaskItem task, DateTime scheduledTime) {
    final duration = scheduledTime.difference(DateTime.now());
    if (duration.isNegative) return;

    // 先取消旧的定时器（如果存在）
    cancelReminder(task.id);

    // 简单的内存计时器，应用关闭则失效。
    // 我们存储一个标记，以便在延迟结束时检查任务是否仍然有效
    final timer = Future.delayed(duration, () {
      // 检查定时器是否还在追踪列表中，如果不在说明已被取消
      if (_windowsTimers.containsKey(task.id) && _winNotifier != null) {
        final message = NotificationMessage.fromCustomTemplate(
          task.id,
          group: 'reminders',
        );
        
        // 使用 scenario="alarm" 或 "reminder" 使通知常驻，并添加操作按钮
        final String toastXml = '''
          <toast scenario="alarm">
            <visual>
              <binding template="ToastGeneric">
                <text>任务提醒</text>
                <text>${task.title}</text>
              </binding>
            </visual>
            <actions>
              <action content="开始专注" arguments="action:start_focus_task:${task.id}" />
              <action content="稍后提醒我" arguments="action:snooze_reminder:${task.id}" />
            </actions>
            <audio src="ms-winsoundevent:Notification.Looping.Alarm" loop="true" />
          </toast>
        ''';
        
        _winNotifier!.showNotificationCustomTemplate(message, toastXml);
        _windowsTimers.remove(task.id);
      }
    });
    
    _windowsTimers[task.id] = timer;
    dev.log('[ReminderService] Windows 提醒已加入内存调度: ${task.title}');
  }

  /// 刷新所有未来的提醒（通常在同步后或启动时调用）
  static Future<void> refreshAll(List<TaskItem> tasks) async {
    if (!_initialized) await initialize();
    
    // 先取消所有现有的（可选，Android 覆盖即可，但为了清理已删除任务建议先 Cancel）
    // 这里简单起见，直接覆盖调度
    for (final task in tasks) {
      if (task.reminderAt != null && !task.completed) {
        await scheduleReminder(task);
      }
    }
  }
}
