import 'dart:io';
import 'dart:developer' as dev;
import 'package:audioplayers/audioplayers.dart';
import 'package:windows_notification/windows_notification.dart';
import 'package:windows_notification/notification_message.dart';

/// 计时器铃声与系统通知服务
/// 职责：
///   1. 播放 assets/audio/alarm.wav 铃声（audioplayers）
///   2. 发送 Windows 操作中心 Toast 通知（windows_notification）
class TimerNotificationService {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // Windows 通知客户端（仅 Windows 平台初始化）
  static WindowsNotification? _winNotifier;

  static bool _initialized = false;

  /// 应在 main() 中调用，初始化通知能力
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 仅在 Windows 下创建通知客户端
    if (Platform.isWindows) {
      try {
        _winNotifier = WindowsNotification(
          // applicationId 需与 Windows 注册的 App User Model ID 匹配，
          // 桌面应用通常使用可执行文件路径
          applicationId:
              r'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',
        );
      } catch (e) {
        dev.log('[TimerNotificationService] Windows 通知初始化失败: $e');
        _winNotifier = null;
      }
    }
  }

  /// 触发计时完成：播放铃声 + 发送 Windows 通知
  /// [title] 通知标题  [body] 通知正文  [soundEnabled] 是否播放铃声
  static Future<void> triggerAlarm({
    required String title,
    required String body,
    bool soundEnabled = true,
  }) async {
    // 确保已初始化
    if (!_initialized) await initialize();

    // 1. 播放铃声
    if (soundEnabled) {
      await _playAlarmSound();
    }

    // 2. Windows 操作中心 Toast 通知
    if (Platform.isWindows && _winNotifier != null) {
      await _sendWindowsToast(title: title, body: body);
    }
  }

  /// 播放内置铃声文件
  static Future<void> _playAlarmSound() async {
    try {
      // 停止可能正在播放的上一次铃声
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('audio/alarm.wav'));
    } catch (e) {
      // 铃声失败时静默降级，不影响计时器主流程
      dev.log('[TimerNotificationService] 铃声播放失败: $e');
    }
  }

  /// 发送 Windows Toast 通知到操作中心
  static Future<void> _sendWindowsToast({
    required String title,
    required String body,
  }) async {
    try {
      final message = NotificationMessage.fromPluginTemplate(
        // 使用时间戳作为唯一 ID，避免通知被覆盖
        'focus_timer_${DateTime.now().millisecondsSinceEpoch}',
        title,
        body,
      );
      await _winNotifier!.showNotificationPluginTemplate(message);
    } catch (e) {
      dev.log('[TimerNotificationService] Windows Toast 发送失败: $e');
    }
  }

  /// 手动停止铃声（如用户点击按钮后调用）
  static Future<void> stopAlarm() async {
    await _audioPlayer.stop();
  }

  /// 释放音频资源（应用退出时调用）
  static Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
