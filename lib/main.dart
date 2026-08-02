import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:focus_my_time/app.dart';
import 'package:focus_my_time/core/platform/application_retry.dart';
import 'package:focus_my_time/core/services/timer_notification_service.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/database/database_platform_initializer.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';
import 'package:focus_my_time/features/ai_assistant/services/deepseek_api_client.dart';

import 'dart:async';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/providers/theme_provider.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (kIsWeb) {
        try {
          await BrowserContextMenu.disableContextMenu();
        } catch (e) {
          debugPrint('Disable browser context menu failed: $e');
        }
      }
      runApp(const _BootstrapApp());

      try {
        await _initializeServices().timeout(const Duration(seconds: 45));

        debugPrint('runApp starting');
        runApp(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, child) {
                final themeMode = ref.watch(themeProvider);
                final themeScheme = ref.watch(themeSchemeProvider);
                return MaterialApp(
                  title: 'FocusMyTime',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightThemeFor(themeScheme),
                  darkTheme: AppTheme.darkThemeFor(themeScheme),
                  themeMode: themeMode,
                  home: const FocusMyTimeApp(),
                );
              },
            ),
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('App initialization failed: $e\n$stackTrace');
        SyncService.stopAutoSync();
        runApp(
          _InitializationErrorApp(
            timedOut: e is TimeoutException,
            onRetry: () => retryApplication(main),
          ),
        );
      }
    },
    (error, stackTrace) {
      debugPrint('Unhandled global error: $error\n$stackTrace');
    },
  );
}

Future<void> _initializeServices() async {
  debugPrint('Init starting');
  await initializeDatabasePlatform();

  debugPrint('AppTime.configure() starting');
  final timeZoneModeValue = await AppDatabase.getSetting(AppTime.settingKey);
  AppTime.configure(AppTime.modeFromValue(timeZoneModeValue));
  debugPrint('AppTime.configure() finished');

  debugPrint('SyncService.init() starting');
  await SyncService.init();
  debugPrint('SyncService.init() finished');
  if (SyncService.isLoggedIn) {
    SyncService.startAutoSync();
  }

  debugPrint('TimerNotificationService.initialize() starting');
  await TimerNotificationService.initialize();
  debugPrint('TimerNotificationService.initialize() finished');

  debugPrint('ReminderService.initialize() starting');
  await ReminderService.initialize();
  debugPrint('ReminderService.initialize() finished');

  debugPrint('DeepSeekApiClient.init() starting');
  await DeepSeekApiClient.init();
  debugPrint('DeepSeekApiClient.init() finished');
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _InitializationErrorApp extends StatelessWidget {
  const _InitializationErrorApp({
    required this.timedOut,
    required this.onRetry,
  });

  final bool timedOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 44),
                    const SizedBox(height: 18),
                    Text(
                      timedOut ? '初始化超时' : '暂时无法启动应用',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      timedOut
                          ? '本地数据加载时间过长，请检查网络或浏览器存储权限后重试。'
                          : '本地数据初始化失败。你的现有数据不会因此被清除，请重试。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
