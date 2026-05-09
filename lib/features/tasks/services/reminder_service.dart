import 'dart:io';
import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:windows_notification/windows_notification.dart';
import 'package:windows_notification/notification_message.dart';
import '../providers/task_provider.dart';
import 'package:focus_my_time/features/calendar/services/calendar_service.dart';
import 'package:focus_my_time/data/database/app_database.dart';

/// 任务提醒服务
/// 职责：管理任务的定时提醒通知，支持 Android (系统级调度) 和 Windows (应用级调度)
class ReminderService {
  static final FlutterLocalNotificationsPlugin _androidPlugin = FlutterLocalNotificationsPlugin();
  static WindowsNotification? _winNotifier;
  static bool _initialized = false;
  
  // 用于追踪 Windows 端的内存定时器，以便在任务删除或提醒更改时取消它们
  static final Map<String, dynamic> _windowsTimers = {};
  static bool _refreshInProgress = false; // 防止并发 refreshAll
  static bool _refreshPending = false; // 有等待中的 refreshAll 请求

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
    
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      dev.log('[ReminderService] 时区解析失败: $timeZoneName, 尝试降级策略。$e');
      try {
        final offsetHours = DateTime.now().timeZoneOffset.inHours;
        if (offsetHours == 8) {
          tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
        } else {
          tz.setLocalLocation(tz.UTC);
        }
      } catch (fallbackError) {
        tz.setLocalLocation(tz.UTC);
      }
    }

    // 2. 初始化 Android 通知
    if (Platform.isAndroid) {
      // Android 13+ 需要显式请求通知权限
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // Android 12+ 检查并引导开启精确闹钟权限
      if (await Permission.scheduleExactAlarm.isDenied || await Permission.scheduleExactAlarm.isPermanentlyDenied) {
        dev.log('[ReminderService] 精确闹钟权限未授予，尝试请求...');
        // 注意：在某些 Android 版本上 request() 可能不会弹出对话框，而是返回 false
        // 最好在 UI 上引导用户去设置页面
        await Permission.scheduleExactAlarm.request();
      }

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
        playSound: true,
        enableVibration: true,
      );
      await _androidPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }

    // 3. 初始化 Windows 通知客户端
    // 注意：与 TimerNotificationService 共享同一个 applicationId，
    // 两个实例的回调都指向 _handleNotificationAction，实际运行中无冲突
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

  /// 发送一个即时测试通知，用于验证通知通道是否畅通
  static Future<void> showImmediateTestNotification() async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'task_reminders',
        '任务提醒',
        importance: Importance.max,
        priority: Priority.high,
      );
      const NotificationDetails details = NotificationDetails(android: androidDetails);
      await _androidPlugin.show(999, '测试通知', '如果你看到了这条消息，说明通知通道正常。', details);
    } else if (Platform.isWindows) {
      final message = NotificationMessage.fromCustomTemplate('test_id', group: 'test');
      const String toastXml = r'''
        <toast>
          <visual>
            <binding template="ToastGeneric">
              <text>测试通知</text>
              <text>如果你看到了这条消息，说明通知通道正常。</text>
            </binding>
          </visual>
        </toast>
      ''';
      _winNotifier?.showNotificationCustomTemplate(message, toastXml);
    }
  }

  /// 获取当前权限状态字符串
  static Future<Map<String, String>> getPermissionStatus() async {
    final status = <String, String>{};
    if (Platform.isAndroid) {
      status['Notification'] = (await Permission.notification.status).toString();
      try {
        status['Exact Alarm'] = (await Permission.scheduleExactAlarm.status).toString();
        status['Battery Optimization'] = (await Permission.ignoreBatteryOptimizations.status).toString();
      } catch (e) {
        status['Exact Alarm'] = 'Error';
      }
    } else {
      status['Platform'] = 'Windows (Not required)';
    }
    return status;
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
    // 如果提醒时间是过去，取消已有定时器防止过期提醒还在队列中排队
    if (reminderDateTime.isBefore(DateTime.now())) {
      dev.log('[ReminderService] 提醒时间已过期: ${task.title}');
      await cancelReminder(task.id);
      return;
    }

    if (Platform.isAndroid) {
      await _scheduleAndroid(task, reminderDateTime);
    } else if (Platform.isWindows) {
      await _scheduleWindows(task, reminderDateTime);
    }
  }

  /// 统一调度提醒（优先日历，其次通知）
  static Future<String?> scheduleUnifiedReminders(TaskItem task) async {
    if (!_initialized) await initialize();

    if (task.reminderAt == null || task.completed) {
      await cancelReminder(task.id);
      if (task.calendarEventId != null) {
        await CalendarService.removeTask(task.calendarEventId!);
        await AppDatabase.updateTask(task.id, {'calendarEventId': null});
      }
      return null;
    }

    // 检查日历权限和启用状态（try-catch 保护：桌面平台可能抛 MissingPluginException）
    bool hasCalendarPermission = false;
    bool calendarEnabled = false;
    try {
      hasCalendarPermission = await CalendarService.hasPermissions();
      calendarEnabled = await CalendarService.isEnabled();
    } catch (e) {
      dev.log('[ReminderService] 日历权限检查失败（预期桌面平台）: $e');
    }

    // 检查通知权限
    final bool hasNotificationPermission = await Permission.notification.isGranted;

    dev.log('[ReminderService] 权限检查 - 日历: $hasCalendarPermission, 启用: $calendarEnabled, 通知: $hasNotificationPermission');

    if (hasCalendarPermission && calendarEnabled) {
      dev.log('[ReminderService] 优先使用日历同步: ${task.title}');
      // try-catch 保护：日历操作在桌面平台或权限异常时可能失败
      try {
        final eventId = await CalendarService.syncTask(task);
        if (eventId != null && eventId != task.calendarEventId) {
          await AppDatabase.updateTask(task.id, {'calendarEventId': eventId});
        }
        await cancelReminder(task.id);
        return eventId;
      } catch (e) {
        dev.log('[ReminderService] 日历同步失败，回退到通知: ${task.title}, $e');
        // 日历失败后回退到系统通知
        if (hasNotificationPermission) {
          await scheduleReminder(task);
        }
        return task.calendarEventId;
      }
    } else if (hasNotificationPermission) {
      dev.log('[ReminderService] 使用系统通知: ${task.title}');
      await scheduleReminder(task);
      if (task.calendarEventId != null) {
        try {
          await CalendarService.removeTask(task.calendarEventId!);
        } catch (e) {
          dev.log('[ReminderService] 清理日历事件失败（预期桌面平台）: $e');
        }
        await AppDatabase.updateTask(task.id, {'calendarEventId': null});
      }
      return null;
    } else {
      dev.log('[ReminderService] 无任何提醒权限: ${task.title}');
      return task.calendarEventId;
    }
  }

  /// 检查是否至少有一个提醒权限可用（日历或通知）
  static Future<bool> hasAnyReminderPermission() async {
    if (!_initialized) await initialize();

    // try-catch 保护：桌面平台调用日历/通知插件可能抛 MissingPluginException
    try {
      final bool hasCalendarPermission = await CalendarService.hasPermissions();
      final bool calendarEnabled = await CalendarService.isEnabled();
      final bool hasNotificationPermission = await Permission.notification.isGranted;
      return (hasCalendarPermission && calendarEnabled) || hasNotificationPermission;
    } catch (e) {
      dev.log('[ReminderService] 权限检查异常（预期桌面平台）: $e');
      // 桌面平台回退：仅检查通知权限
      try {
        return await Permission.notification.isGranted;
      } catch (_) {
        return false;
      }
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
        // Timer 支持 cancel()，可真正阻止回调执行
        if (existingTimer is Timer) {
          existingTimer.cancel();
        } else if (existingTimer is StreamSubscription) {
          existingTimer.cancel();
        } else if (existingTimer is Future) {
          // Future 无法直接取消，仅作兼容保留
        }
        _windowsTimers.remove(taskId);
      }
    }
  }

  static Future<void> _scheduleAndroid(TaskItem task, DateTime scheduledTime) async {
    final int notificationId = task.id.hashCode;

    // 先取消旧调度再创建新的，防止部分 OEM 设备出现重复通知
    await _androidPlugin.cancel(notificationId);

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
          priority: Priority.max,
          showWhen: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task:${task.id}',
    );
    dev.log('[ReminderService] Android 提醒已调度: ${task.title} at $scheduledTime');
  }

  static Future<void> _scheduleWindows(TaskItem task, DateTime scheduledTime) async {
    final duration = scheduledTime.difference(DateTime.now());
    if (duration.isNegative) return;

    // 先取消旧的定时器，Timer.cancel() 可真正阻止旧回调执行
    await cancelReminder(task.id);

    // 使用 Timer 而非 Future.delayed：Timer 支持 cancel()，
    // 确保修改提醒时间后旧定时器的回调不会误触发
    final timer = Timer(duration, () {
      if (_winNotifier != null) {
        final message = NotificationMessage.fromCustomTemplate(
          task.id,
          group: 'reminders',
        );

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
      }
      _windowsTimers.remove(task.id);
      // 提醒已触发，清除数据库中的 reminder_at 防止死数据累积
      AppDatabase.updateTask(task.id, {'reminderAt': null});
    });

    _windowsTimers[task.id] = timer;
    dev.log('[ReminderService] Windows 提醒已加入内存调度: ${task.title}');
  }

  /// 请求忽略电池优化 (Android 专用)
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      } else {
        // 如果已经请求过但仍然被优化，可以引导去设置
        openAppSettings();
      }
    }
  }

  /// 请求精确闹钟权限 (Android 专用)
  static Future<void> requestExactAlarmPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isGranted) {
        dev.log('[ReminderService] 精确闹钟权限已授予');
      } else {
        // 在某些 Android 13+ 设备上，request() 可能无反应，
        // 此时引导用户去系统设置页面的“闹钟与提醒”手动开启
        await Permission.scheduleExactAlarm.request();
        // 如果请求后仍未授予，尝试打开应用设置或特定权限页面
        if (!(await Permission.scheduleExactAlarm.isGranted)) {
          await openAppSettings();
        }
      }
    }
  }

  /// 刷新所有未来的提醒（通常在启动或同步后调用）
  /// 仅调度未来的提醒，过期的跳过（不自动删除——保留用户数据）
  static Future<void> refreshAll(List<TaskItem> tasks) async {
    // 如果已有 refreshAll 正在执行，标记待重跑，等当前执行完后自动重跑一次
    if (_refreshInProgress) {
      _refreshPending = true;
      return;
    }
    _refreshInProgress = true;
    try {
      await _doRefreshAll(tasks);
      // 如果在执行期间收到了新的 refreshAll 请求，再跑一次（合并多次请求）
      while (_refreshPending) {
        _refreshPending = false;
        await _doRefreshAll(tasks);
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  static Future<void> _doRefreshAll(List<TaskItem> tasks) async {
    if (!_initialized) await initialize();

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final missedThreshold = nowMs - 30 * 60 * 1000; // 过去 30 分钟（仅 Windows 用）

    for (final task in tasks) {
      if (task.reminderAt == null || task.completed) continue;

      final reminderTime = DateTime.fromMillisecondsSinceEpoch(task.reminderAt!);
      if (reminderTime.isAfter(now)) {
        // 未来提醒：正常调度
        await scheduleUnifiedReminders(task);
      } else if (Platform.isWindows &&
          task.reminderAt! >= missedThreshold &&
          _winNotifier != null) {
        // Windows 端：检测刚错过的提醒（APP 关闭期间的提醒）
        // 使用 task.id 作为 tag 防止重复弹窗
        final message = NotificationMessage.fromCustomTemplate(
          'missed_${task.id}',
          group: 'reminders',
        );
        final String toastXml = '''
          <toast>
            <visual>
              <binding template="ToastGeneric">
                <text>错过了提醒</text>
                <text>${task.title}</text>
              </binding>
            </visual>
          </toast>
        ''';
        _winNotifier!.showNotificationCustomTemplate(message, toastXml);
      }
      // 过期提醒不自动删除 reminder_at，保留用户数据
    }
  }

  /// 触发一个立即生效的系统闹钟提醒（全屏、高优先级）
  static Future<void> triggerTestAlarm() async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid) {
      await _androidPlugin.show(
        888,
        '测试系统闹钟',
        '这是一条模拟任务到期的全屏提醒测试。',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            '任务提醒',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
      );
    }
  }
}
