import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:focus_my_time/app.dart';
import 'package:focus_my_time/core/services/timer_notification_service.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';
import 'package:focus_my_time/features/ai_assistant/services/deepseek_api_client.dart';

import 'dart:async';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/providers/theme_provider.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      debugPrint('Init starting');
      // 初始化桌面端 SQLite FFI（Android/iOS 不需要此步骤）
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      debugPrint('AppTime.configure() starting');
      final timeZoneModeValue =
          await AppDatabase.getSetting(AppTime.settingKey);
      AppTime.configure(AppTime.modeFromValue(timeZoneModeValue));
      debugPrint('AppTime.configure() finished');

      debugPrint('SyncService.init() starting');
      // 初始化同步服务，从本地数据库加载登录状态
      await SyncService.init();
      debugPrint('SyncService.init() finished');

      // 如果已登录，启动周期性后台同步
      if (SyncService.isLoggedIn) {
        SyncService.startAutoSync();
      }

      debugPrint('TimerNotificationService.initialize() starting');
      // 初始化计时器通知服务（铃声 + Windows Toast + 本地弹窗）
      await TimerNotificationService.initialize();
      debugPrint('TimerNotificationService.initialize() finished');

      debugPrint('ReminderService.initialize() starting');
      // 初始化任务提醒服务
      await ReminderService.initialize();
      debugPrint('ReminderService.initialize() finished');

      debugPrint('DeepSeekApiClient.init() starting');
      // 初始化 AI 助手 API 客户端
      await DeepSeekApiClient.init();
      debugPrint('DeepSeekApiClient.init() finished');

      debugPrint('runApp starting');
      runApp(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, child) {
              final themeMode = ref.watch(themeProvider);
              return MaterialApp(
                title: 'FocusMyTime',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                home: const FocusMyTimeApp(),
              );
            },
          ),
        ),
      );
    } catch (e, stackTrace) {
      runApp(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.red[900],
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'App Initialization Error:\n\n$e\n\n$stackTrace',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }, (error, stackTrace) {
    debugPrint('Unhandled global error: $error\n$stackTrace');
  });
}
