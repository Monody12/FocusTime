import 'dart:io';
import 'dart:developer' as dev;
import 'package:audioplayers/audioplayers.dart';
import 'package:windows_notification/windows_notification.dart';
import 'package:windows_notification/notification_message.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 计时器铃声与系统通知服务
/// 职责：
///   1. 播放 assets/audio/alarm.wav 铃声（audioplayers, 支持循环模式）
///   2. 发送 Windows 操作中心 Toast 通知（windows_notification）
///   3. 发送 Android 本地通知（flutter_local_notifications）
class TimerNotificationService {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // Windows 通知客户端（仅 Windows 平台初始化）
  static WindowsNotification? _winNotifier;

  // Android 通知插件
  static final FlutterLocalNotificationsPlugin _androidNotifier = FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // 外部监听通知动作的回调
  static Function(String)? _onAction;

  /// 应在 main() 中调用，初始化通知能力
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    dev.log('[TimerNotificationService] 正在初始化通知服务...');

    // 1. 设置音频播放器为循环模式
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);

    // 2. 仅在 Windows 下创建通知客户端
    if (Platform.isWindows) {
      _initWindowsNotifier();
    }

    // 3. 在 Android 下初始化通知插件
    if (Platform.isAndroid) {
      await _initAndroidNotifier();
    }
  }

  static void _initWindowsNotifier() {
    try {
      _winNotifier = WindowsNotification(
        applicationId: r'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',
      );

      _winNotifier!.initNotificationCallBack((details) {
        final String? arguments = details.argrument;
        dev.log('[TimerNotificationService] 通知被激活, 动作: $arguments');
        if (arguments != null && _onAction != null) {
          _onAction!(arguments);
        }
      });
    } catch (e) {
      dev.log('[TimerNotificationService] Windows 通知初始化失败: $e');
    }
  }

  static Future<void> _initAndroidNotifier() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _androidNotifier.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.actionId ?? response.payload;
        dev.log('[TimerNotificationService] Android 通知动作: $payload');
        if (payload != null && _onAction != null) {
          // payload 可能是 'action:start_break' 这种格式，
          // 但 flutter_local_notifications 的 actionId 是直接的 ID
          final String normalizedPayload = payload.startsWith('action:') ? payload : 'action:$payload';
          _onAction!(normalizedPayload);
        }
      },
    );

    // 创建通知渠道（Android 8.0+）
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'focus_timer_channel',
      '专注计时器',
      description: '用于发送计时结束的提醒',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _androidNotifier
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 注册通知动作监听器
  static void setActionListener(Function(String) listener) {
    _onAction = listener;
  }

  /// 触发计时完成
  static Future<void> triggerAlarm({
    required String title,
    required String body,
    bool soundEnabled = true,
    String phase = 'focus',
    String duration = 'long',
  }) async {
    if (!_initialized) await initialize();

    // 1. 响铃处理
    if (!Platform.isWindows && soundEnabled) {
      final bool loop = duration == 'persistent';
      await _playAlarmSound(loop: loop);
    }

    // 2. 发送通知
    if (Platform.isWindows && _winNotifier != null) {
      await _sendActionableToast(title: title, body: body, phase: phase, duration: duration);
    } else if (Platform.isAndroid) {
      await _sendAndroidNotification(title: title, body: body, phase: phase);
    }
  }

  static Future<void> _sendAndroidNotification({
    required String title,
    required String body,
    required String phase,
  }) async {
    final List<AndroidNotificationAction> actions = [];
    if (phase == 'focus') {
      actions.add(const AndroidNotificationAction('start_break', '开始休息', showsUserInterface: true));
      actions.add(const AndroidNotificationAction('start_focus', '继续专注', showsUserInterface: true));
    } else {
      actions.add(const AndroidNotificationAction('start_focus', '开始专注', showsUserInterface: true));
      actions.add(const AndroidNotificationAction('skip_break', '跳过休息', showsUserInterface: true));
    }

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'focus_timer_channel',
      '专注计时器',
      channelDescription: '用于发送计时结束的提醒',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      actions: actions,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _androidNotifier.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: 'action:none',
    );
  }

  /// 播放内置铃声文件
  static Future<void> _playAlarmSound({bool loop = true}) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await _audioPlayer.play(AssetSource('audio/alarm.wav'));
    } catch (e) {
      dev.log('[TimerNotificationService] 铃声播放失败: $e');
    }
  }

  /// 发送带操作按钮的 Windows Toast 通知
  static Future<void> _sendActionableToast({
    required String title,
    required String body,
    required String phase,
    required String duration,
  }) async {
    try {
      final String scenario = duration == 'persistent'
          ? 'alarm'
          : (duration == 'long' ? 'reminder' : 'default');
      
      const String audioSrc = 'ms-winsoundevent:Notification.Looping.Alarm';
      final String loopingAttr = duration != 'short' ? ' loop="true"' : ' loop="false"';

      String actionsXml = '';
      if (phase == 'focus') {
        actionsXml = '''
          <action content="开始休息" arguments="action:start_break" />
          <action content="继续专注" arguments="action:start_focus" />
        ''';
      } else {
        actionsXml = '''
          <action content="开始专注" arguments="action:start_focus" />
          <action content="跳过休息" arguments="action:skip_break" />
        ''';
      }

      final String toastXml = '''
        <toast scenario="$scenario">
          <visual>
            <binding template="ToastGeneric">
              <text>$title</text>
              <text>$body</text>
            </binding>
          </visual>
          <actions>
            $actionsXml
          </actions>
          <audio src="$audioSrc" $loopingAttr />
        </toast>
      ''';

      final message = NotificationMessage.fromCustomTemplate(
        'timer_completion',
        group: 'focus_my_time',
      );

      await _winNotifier!.showNotificationCustomTemplate(message, toastXml);
    } catch (e) {
      dev.log('[TimerNotificationService] Windows Actionable Toast 发送失败: $e');
    }
  }

  /// 手动停止铃声
  static Future<void> stopAlarm() async {
    dev.log('[TimerNotificationService] 停止铃声并尝试清除系统通知');
    await _audioPlayer.stop();
    
    if (Platform.isWindows && _winNotifier != null) {
      try {
        _winNotifier!.removeNotificationId('timer_completion', 'focus_my_time');
      } catch (e) {
        dev.log('[TimerNotificationService] 清除 Windows 通知失败: $e');
      }
    } else if (Platform.isAndroid) {
      await _androidNotifier.cancel(0);
    }
  }

  /// 释放音频资源
  static Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
