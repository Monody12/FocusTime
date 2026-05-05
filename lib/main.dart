import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/services/timer_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化桌面端 SQLite FFI（Android/iOS 不需要此步骤）
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 初始化计时器通知服务（铃声 + Windows Toast + 本地弹窗）
  await TimerNotificationService.initialize();

  runApp(
    const ProviderScope(
      child: FocusTimerApp(),
    ),
  );
}