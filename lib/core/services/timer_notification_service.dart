import 'dart:io';
import 'dart:developer' as dev;
import 'package:audioplayers/audioplayers.dart';
import 'package:windows_notification/windows_notification.dart';
import 'package:windows_notification/notification_message.dart';

/// 计时器铃声与系统通知服务
/// 职责：
///   1. 播放 assets/audio/alarm.wav 铃声（audioplayers, 支持循环模式）
///   2. 发送 Windows 操作中心 Toast 通知（windows_notification, 支持自定义按钮交互）
class TimerNotificationService {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // Windows 通知客户端（仅 Windows 平台初始化）
  static WindowsNotification? _winNotifier;

  static bool _initialized = false;

  // 外部监听通知动作的回调
  static Function(String)? _onAction;

  /// 应在 main() 中调用，初始化通知能力
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. 设置音频播放器为循环模式，直到用户手动停止
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);

    // 2. 仅在 Windows 下创建通知客户端
    if (Platform.isWindows) {
      try {
        _winNotifier = WindowsNotification(
          // applicationId 建议为 null 以匹配 Flutter 编译后的 AUMID，
          // 或者指定具体的 ID。PowerShell ID 是开发阶段的临时兼容方案。
          applicationId: r'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',
        );

        // 注册通知点击/动作回调
        _winNotifier!.initNotificationCallBack((details) {
          // 注意：windows_notification 插件在这里有一个拼写错误，属性名是 argrument 而非 argument
          final String? arguments = details.argrument;
          dev.log('[TimerNotificationService] 通知被激活, 动作: $arguments');
          if (arguments != null && _onAction != null) {
            _onAction!(arguments);
          }
        });
      } catch (e) {
        dev.log('[TimerNotificationService] Windows 通知初始化失败: $e');
        _winNotifier = null;
      }
    }
  }

  /// 注册通知动作监听器（由 TimerNotifier 调用）
  static void setActionListener(Function(String) listener) {
    _onAction = listener;
  }

  /// 触发计时完成：播放铃声 + 发送 Windows 通知
  /// [title] 通知标题  [body] 通知正文  [soundEnabled] 是否播放铃声
  /// [phase] 当前阶段，用于决定通知按钮
  /// [duration] 持续模式：short, long, persistent
  static Future<void> triggerAlarm({
    required String title,
    required String body,
    bool soundEnabled = true,
    String phase = 'focus',
    String duration = 'long',
  }) async {
    // 确保已初始化
    if (!_initialized) await initialize();

    // 1. 响铃处理
    // 复刻老架构：Windows 平台优先使用 Toast 自带的系统音（声音更好听且支持系统级循环）
    // 如果不是 Windows 平台，或者 soundEnabled 为 false，则使用 audioplayers 作为兜底
    if (!Platform.isWindows && soundEnabled) {
      final bool loop = duration == 'persistent';
      await _playAlarmSound(loop: loop);
    }

    // 2. Windows 操作中心 Toast 通知（包含交互按钮）
    if (Platform.isWindows && _winNotifier != null) {
      await _sendActionableToast(title: title, body: body, phase: phase, duration: duration);
    }
  }

  /// 播放内置铃声文件
  static Future<void> _playAlarmSound({bool loop = true}) async {
    try {
      // 停止可能正在播放的上一次铃声
      await _audioPlayer.stop();
      // 根据参数决定是否循环播放
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
      // 1. 映射持续时间到 Windows Toast Scenario 和系统提示音
      // 复刻老架构逻辑，但确保所有模式下都使用"闹钟"声音，而非默认的消息提示音
      // persistent -> scenario="alarm", audio="Notification.Looping.Alarm", loop="true"
      // long -> scenario="reminder", audio="Notification.Looping.Alarm", loop="false"
      // short -> scenario="default", audio="Notification.Looping.Alarm", loop="false"
      final String scenario = duration == 'persistent'
          ? 'alarm'
          : (duration == 'long' ? 'reminder' : 'default');
      
      final String audioSrc = 'ms-winsoundevent:Notification.Looping.Alarm';
      
      final String loopingAttr = duration != 'short' ? ' loop="true"' : ' loop="false"';

      // 2. 根据阶段构建按钮
      String actionsXml = '';
      if (phase == 'focus') {
        actionsXml = '''
          <action content="开始休息" arguments="action:start_break" />
          <action content="忽略" arguments="action:stop_alarm" />
        ''';
      } else {
        actionsXml = '''
          <action content="开始专注" arguments="action:start_focus" />
          <action content="跳过休息" arguments="action:skip_break" />
        ''';
      }

      // 3. 构造 Toast XML
      // 完整复刻老架构的 XML 结构和音频配置
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
        group: 'focus_timer',
      );

      await _winNotifier!.showNotificationCustomTemplate(message, toastXml);
    } catch (e) {
      dev.log('[TimerNotificationService] Windows Actionable Toast 发送失败: $e');
    }
  }

  /// 手动停止铃声（如用户点击按钮后调用）
  static Future<void> stopAlarm() async {
    dev.log('[TimerNotificationService] 停止铃声并尝试清除系统通知');
    // 停止本地音频播放器
    await _audioPlayer.stop();
    
    // 隐藏的 Bug 修复：
    // 在 Windows 系统中，如果 Toast 配置了 loop="true"，声音是由操作系统接管的。
    // 仅仅停止 _audioPlayer 无法停止系统级的 Toast 声音。
    // 必须通过移除该通知来让系统自动停止发声。
    if (Platform.isWindows && _winNotifier != null) {
      try {
        _winNotifier!.removeNotificationId('timer_completion', 'focus_timer');
      } catch (e) {
        dev.log('[TimerNotificationService] 清除 Windows 通知失败: $e');
      }
    }
  }

  /// 释放音频资源
  static Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
