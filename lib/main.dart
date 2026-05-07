import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/services/timer_notification_service.dart';
import 'data/sync/sync_service.dart';
import 'features/tasks/services/reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化桌面端 SQLite FFI（Android/iOS 不需要此步骤）
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 初始化同步服务，从本地数据库加载登录状态
  await SyncService.init();

  // 初始化计时器通知服务（铃声 + Windows Toast + 本地弹窗）
  await TimerNotificationService.initialize();

  // 初始化任务提醒服务
  await ReminderService.initialize();

  runApp(
    const ProviderScope(
      child: FocusMyTimeApp(),
    ),
  );
}
