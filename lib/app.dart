import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/providers/time_zone_provider.dart';
import 'package:focus_my_time/core/providers/theme_provider.dart';
import 'package:focus_my_time/core/platform/platform_info.dart';
import 'package:focus_my_time/features/sidebar/presentation/widgets/sidebar.dart';
import 'package:focus_my_time/features/timer/presentation/pages/timer_page.dart';
import 'package:focus_my_time/features/tasks/presentation/pages/task_list_page.dart';
import 'package:focus_my_time/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:focus_my_time/features/settings/presentation/pages/settings_page.dart';
import 'package:focus_my_time/features/calendar/presentation/pages/calendar_page.dart';
import 'package:focus_my_time/features/calendar/presentation/pages/calendar_task_detail_page.dart';
import 'package:focus_my_time/features/ai_assistant/presentation/pages/ai_chat_page.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/core/providers/package_info_provider.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/update/services/update_service.dart';
import 'package:focus_my_time/features/update/presentation/widgets/update_dialog.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/presentation/pages/memo_page.dart';

class FocusMyTimeApp extends ConsumerStatefulWidget {
  const FocusMyTimeApp({super.key});

  @override
  ConsumerState<FocusMyTimeApp> createState() => _FocusMyTimeAppState();
}

class _FocusMyTimeAppState extends ConsumerState<FocusMyTimeApp>
    with WidgetsBindingObserver {
  static const MethodChannel _androidBackChannel = MethodChannel(
    'focus_my_time/android_back',
  );

  bool _showTimerPanel = false; // 默认不显示计时器，开始专注后才显示
  bool _showSettings = false;
  bool _showCalendar = false;
  String? _calendarTaskId;
  bool _showAiChat = false;
  bool _showMemos = false;
  bool _showNoTaskToast = false;
  Timer? _foregroundSyncDebounce;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PlatformInfo.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _scheduleAndroidForegroundSync();
    unawaited(MemoCryptoService.instance.loadPersistedSettings());
    // 延迟检查更新，避免阻塞首屏
    Future.delayed(const Duration(seconds: 2), _checkUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundSyncDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAndroidForegroundSync();
      MemoCryptoService.instance.onAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      MemoCryptoService.instance.onAppBackground();
    }
  }

  void _scheduleAndroidForegroundSync() {
    if (!PlatformInfo.isAndroid || !SyncService.isLoggedIn) return;
    _foregroundSyncDebounce?.cancel();
    _foregroundSyncDebounce = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      ref.read(taskProvider.notifier).sync(background: true);
    });
  }

  Future<void> _checkUpdate() async {
    final updateInfo = await UpdateService.checkForUpdates();
    if (updateInfo != null && mounted) {
      UpdateDialog.show(context, updateInfo);
    }
  }

  @override
  Widget build(BuildContext context) {
    // final timerState = ref.watch(timerProvider); // Removed to prevent global rebuilds
    final timerNotifier = ref.read(timerProvider.notifier);
    ref.watch(timeZoneProvider);
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final taskState = ref.watch(taskProvider);

    final size = MediaQuery.of(context).size;
    final viewPadding = MediaQuery.paddingOf(context);
    final isMobile = size.width < 800;
    final usesSystemInsets = PlatformInfo.isAndroid || PlatformInfo.isIOS;
    final topInset = usesSystemInsets ? viewPadding.top : 0.0;
    final bottomInset = usesSystemInsets ? viewPadding.bottom : 0.0;

    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final topBarColor = isDark
        ? context.appColors.sidebar
        : context.appColors.surface;
    final systemUiStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: context.appColors.background,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    // Auto-open timer panel when transition to running
    ref.listen(timerProvider, (previous, next) {
      final wasRunning = previous?.timerStatus == TimerStatus.running;
      final isRunning = next.timerStatus == TimerStatus.running;
      if (isRunning && !wasRunning && _showTimerPanel == false) {
        setState(() => _showTimerPanel = true);
      }
    });

    // 记录最后停留的清单；即时保存也能覆盖 Web 标签页被直接关闭的场景。
    ref.listen(taskProvider, (previous, next) {
      if (previous != null && previous.currentListId != next.currentListId) {
        unawaited(_persistLastViewedList(next.currentListId));
      }
    });

    /// 移动端抽屉底部功能入口：顶栏精简后，备忘录/AI/同步/主题切换统一收在这里。
  Widget buildMobileDrawerActions(ThemeNotifier themeNotifier) {
    final entries = <(String, IconData, VoidCallback)>[
      (
        '备忘录',
        AppIcons.memo,
        () => setState(() {
          _showMemos = !_showMemos;
          _showCalendar = false;
          _showSettings = false;
        }),
      ),
      (
        'AI 助手',
        AppIcons.ai,
        () => setState(() {
          _showAiChat = true;
          _showMemos = false;
        }),
      ),
      ('立即同步', AppIcons.reset, () => _syncNow()),
      (
        '切换主题',
        AppIcons.lightMode,
        () => themeNotifier.toggleTheme(),
      ),
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, icon, onTap) in entries)
            ListTile(
              dense: true,
              leading: Icon(icon, size: 20, color: context.appColors.text),
              title: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: context.appColors.text,
                ),
              ),
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                onTap();
              },
            ),
        ],
      ),
    );
  }

  Widget mainContent = Scaffold(
      key: _scaffoldKey, // For drawer access
      backgroundColor: context.appColors.background,
      drawer: isMobile
          ? Drawer(
              width: 280,
              backgroundColor: context.appColors.sidebar,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(18),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: Sidebar(
                      topPadding: topInset + 10,
                      showRightBorder: false,
                      onListChanged: () {
                        ref.read(taskProvider.notifier).setSelectedTask(null);
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  buildMobileDrawerActions(themeNotifier),
                ],
              ),
            )
          : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                // Header (Top-level, spans full width)
                Container(
                  padding: EdgeInsets.fromLTRB(18, topInset + 12, 18, 12),
                  decoration: BoxDecoration(
                    color: topBarColor,
                    border: Border(
                      bottom: BorderSide(color: context.appColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isMobile)
                        Builder(
                          builder: (context) => IconButton(
                            icon: const Icon(AppIcons.menu),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            color: context.appColors.text,
                          ),
                        ),
                      // 应用标题
                      Text(
                        'FocusMyTime',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? context.appColors.accentSecondary
                              : context.appColors.accent,
                        ),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<String>(
                        valueListenable: SyncService.syncWarningListenable,
                        builder: (context, warning, _) {
                          if (warning.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _showSettings = true),
                              icon: const Icon(
                                AppIcons.warning,
                                size: AppIconSizes.nav,
                              ),
                              label: isMobile
                                  ? const SizedBox.shrink()
                                  : const Text('同步需登录'),
                              style: TextButton.styleFrom(
                                foregroundColor: context.appColors.warning,
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Theme toggle（移动端收进抽屉）
                      if (!isMobile)
                        IconButton(
                          icon: Icon(
                            isDark ? AppIcons.lightMode : AppIcons.darkMode,
                            size: AppIconSizes.nav,
                          ),
                          onPressed: () => themeNotifier.toggleTheme(),
                          tooltip: '切换主题',
                          color: context.appColors.text,
                        ),
                      const SizedBox(width: 4),
                      // 移动端顶栏只保留 设置（其余入口收进抽屉，避免溢出）；
                      // 桌面端保持完整按钮排。
                      if (!isMobile) ...[
                        IconButton(
                          icon: const Icon(
                            AppIcons.reset,
                            size: AppIconSizes.nav,
                          ),
                          onPressed: () => _syncNow(),
                          tooltip: '同步',
                          color: context.appColors.text,
                        ),
                        const SizedBox(width: 4),
                        // AI Assistant button
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _showMemos = !_showMemos;
                            _showCalendar = false;
                            _showSettings = false;
                          }),
                          icon: const Icon(AppIcons.memo, size: AppIconSizes.nav),
                          label: const Text('备忘录'),
                          style: TextButton.styleFrom(
                            foregroundColor: context.appColors.text,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: () => setState(() => _showAiChat = true),
                          icon: const Icon(AppIcons.ai, size: AppIconSizes.nav),
                          label: const Text('AI'),
                          style: TextButton.styleFrom(
                            foregroundColor: context.appColors.text,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Settings button
                      TextButton.icon(
                        onPressed: () => setState(() => _showSettings = true),
                        icon: const Icon(
                          AppIcons.settings,
                          size: AppIconSizes.nav,
                        ),
                        label: isMobile ? const Text('') : const Text('设置'),
                        style: TextButton.styleFrom(
                          foregroundColor: context.appColors.text,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      // Sidebar (Desktop only)
                      if (!isMobile)
                        SizedBox(
                          width: 220,
                          child: Sidebar(
                            onListChanged: () {
                              ref
                                  .read(taskProvider.notifier)
                                  .setSelectedTask(null);
                            },
                          ),
                        ),
                      // Main area content
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _showMemos
                                  ? MemoPage(
                                      onClose: () => setState(
                                        () => _showMemos = false,
                                      ),
                                    )
                                  : _showCalendar
                                  ? CalendarPage(
                                      onTaskSelected: (taskId) {
                                        setState(
                                          () => _calendarTaskId = taskId,
                                        );
                                      },
                                    )
                                  : _buildMainContent(isDark, isMobile),
                            ),
                            // Footer
                            // 移动端备忘录页隐藏专注/日历条，把空间留给内容。
                            if (!(isMobile && _showMemos))
                              Container(
                                padding: EdgeInsets.fromLTRB(
                                  isMobile ? 14 : 16,
                                  isMobile ? 10 : 8,
                                  isMobile ? 14 : 16,
                                  bottomInset + (isMobile ? 14 : 8),
                                ),
                              decoration: BoxDecoration(
                                color: context.appColors.background,
                                border: Border(
                                  top: BorderSide(
                                    color: context.appColors.border,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (_showNoTaskToast)
                                    Flexible(
                                      child: Text(
                                        '⚠ 请先选择一个任务',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color:
                                              context.appColors.textSecondary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  else
                                    Flexible(
                                      child: Consumer(
                                        builder: (context, ref, child) {
                                          final timerState = ref.watch(
                                            timerProvider,
                                          );
                                          final taskState = ref.watch(
                                            taskProvider,
                                          );
                                          return _buildFocusButton(
                                            timerState,
                                            timerNotifier,
                                            taskState,
                                            isDark,
                                            isMobile,
                                          );
                                        },
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () {
                                      final showCalendar = !_showCalendar;
                                      setState(() {
                                        _showCalendar = showCalendar;
                                        _calendarTaskId = null;
                                        if (showCalendar) {
                                          _showSettings = false;
                                        }
                                      });
                                      if (showCalendar) {
                                        ref
                                            .read(taskProvider.notifier)
                                            .setSelectedTask(null);
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 8 : 16,
                                        vertical: 10,
                                      ),
                                      side: BorderSide(
                                        color: context.appColors.border,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppIcon(
                                          AppIcons.calendar,
                                          size: AppIconSizes.compact,
                                          semanticLabel: isMobile ? '日历' : null,
                                          color: _showCalendar
                                              ? context
                                                    .appColors
                                                    .accentSecondary
                                              : context.appColors.text,
                                        ),
                                        if (!isMobile) ...[
                                          const SizedBox(
                                            width: AppIconSpacing.compactGap,
                                          ),
                                          Text(
                                            '日历',
                                            style: TextStyle(
                                              color: _showCalendar
                                                  ? context
                                                        .appColors
                                                        .accentSecondary
                                                  : context.appColors.text,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!isMobile) ...[
                                    const SizedBox(width: 12),
                                    ref
                                        .watch(packageInfoProvider)
                                        .when(
                                          data: (info) => Text(
                                            'v${info.version}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors
                                                        .lightTextSecondary,
                                            ),
                                          ),
                                          loading: () =>
                                              const SizedBox.shrink(),
                                          error: (_, __) =>
                                              const SizedBox.shrink(),
                                        ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Task Detail panel (Desktop only)
                      // We only show it if the selected task is actually in the current list
                      if (!isMobile &&
                          taskState.selectedTaskId != null &&
                          !_showCalendar)
                        TaskDetailPage(
                          taskId: taskState.selectedTaskId!,
                          onClose: () {
                            ref
                                .read(taskProvider.notifier)
                                .setSelectedTask(null);
                          },
                        ),
                      if (!isMobile && _showCalendar && _calendarTaskId != null)
                        CalendarTaskDetailPage(
                          taskId: _calendarTaskId!,
                          onClose: () {
                            setState(() => _calendarTaskId = null);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Task Detail overlay (Mobile only)
          if (isMobile && taskState.selectedTaskId != null && !_showCalendar)
            Positioned.fill(
              child: Container(
                color: context.appColors.background,
                child: TaskDetailPage(
                  taskId: taskState.selectedTaskId!,
                  onClose: () {
                    ref.read(taskProvider.notifier).setSelectedTask(null);
                  },
                ),
              ),
            ),
          if (isMobile && _showCalendar && _calendarTaskId != null)
            Positioned.fill(
              child: Container(
                color: context.appColors.background,
                child: CalendarTaskDetailPage(
                  taskId: _calendarTaskId!,
                  onClose: () {
                    setState(() => _calendarTaskId = null);
                  },
                ),
              ),
            ),

          // Settings overlay
          if (_showSettings)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    width: isMobile ? size.width * 0.9 : 500,
                    height: size.height * 0.8,
                    decoration: BoxDecoration(
                      color: context.appColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SettingsPage(
                      onClose: () => setState(() => _showSettings = false),
                    ),
                  ),
                ),
              ),
            ),
          if (_showAiChat)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    width: isMobile ? size.width * 0.95 : 700,
                    height: size.height * 0.85,
                    decoration: BoxDecoration(
                      color: context.appColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AiChatPage(
                      onClose: () => setState(() => _showAiChat = false),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: PopScope(
        canPop: !PlatformInfo.isAndroid,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleSystemBack(isMobile);
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleDeleteShortcut(event),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyT,
                control: true,
              ): () {
                if (taskState.selectedTaskId != null) {
                  final taskNotifier = ref.read(taskProvider.notifier);
                  final task = taskState.tasks
                      .where((t) => t.id == taskState.selectedTaskId)
                      .firstOrNull;
                  if (task != null) {
                    if (task.isMyDay) {
                      taskNotifier.removeFromMyDay(task.id);
                    } else {
                      taskNotifier.addToMyDay(task.id);
                    }
                  }
                }
              },
              const SingleActivator(
                LogicalKeyboardKey.keyD,
                control: true,
              ): () {
                if (taskState.selectedTaskId != null) {
                  ref
                      .read(taskProvider.notifier)
                      .toggleTaskComplete(taskState.selectedTaskId!);
                }
              },
            },
            child: mainContent,
          ),
        ),
      ),
    );
  }

  Future<void> _persistLastViewedList(String listId) async {
    try {
      await ref.read(taskProvider.notifier).persistLastViewedList(listId);
    } catch (_) {
      if (!mounted) return;
      final scaffoldContext = _scaffoldKey.currentContext;
      if (scaffoldContext == null || !scaffoldContext.mounted) return;
      ScaffoldMessenger.of(
        scaffoldContext,
      ).showSnackBar(const SnackBar(content: Text('保存上次停留清单失败，请重试')));
    }
  }

  KeyEventResult _handleDeleteShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.delete ||
        _isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final taskState = ref.read(taskProvider);
    final selectedTaskId = taskState.selectedTaskId;
    if (selectedTaskId == null) return KeyEventResult.ignored;

    final task = taskState.tasks
        .where((t) => t.id == selectedTaskId)
        .firstOrNull;
    if (task == null) return KeyEventResult.ignored;

    _confirmDeleteTask(context, task);
    return KeyEventResult.handled;
  }

  bool _isTextInputFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<bool> _handleSystemBack(bool isMobile) async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
      return false;
    }

    if (_showSettings) {
      setState(() => _showSettings = false);
      return false;
    }

    if (_showAiChat) {
      setState(() => _showAiChat = false);
      return false;
    }

    final taskNotifier = ref.read(taskProvider.notifier);
    final taskState = ref.read(taskProvider);
    if (taskState.selectedTaskId != null) {
      taskNotifier.setSelectedTask(null);
      return false;
    }

    if (_showCalendar) {
      setState(() => _showCalendar = false);
      return false;
    }

    if (isMobile && _showTimerPanel) {
      setState(() => _showTimerPanel = false);
      return false;
    }

    if (PlatformInfo.isAndroid) {
      try {
        await _androidBackChannel.invokeMethod<void>('moveTaskToBack');
      } catch (_) {
        await SystemNavigator.pop();
      }
      return false;
    }

    return true;
  }

  void _confirmDeleteTask(BuildContext context, TaskItem task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除任务 "${task.title}" 吗？'),
        backgroundColor: context.appColors.surface,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(taskProvider.notifier).deleteTask(task.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    final result = await ref.read(taskProvider.notifier).sync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.success ? '同步完成' : '同步失败，请检查登录和网络')),
    );
  }

  Widget _buildMainContent(bool isDark, bool isMobile) {
    if (_showTimerPanel) {
      if (isMobile) {
        // Mobile: Show TimerPage as a stack or separate view
        return Stack(
          children: [
            const TaskListView(),
            Positioned.fill(
              child: Container(
                color: context.appColors.background,
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(AppIcons.back),
                          onPressed: () =>
                              setState(() => _showTimerPanel = false),
                        ),
                        const Text(
                          '专注计时',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Expanded(child: TimerPage()),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // Desktop grid
      return Row(
        children: [
          const Expanded(child: TaskListView()),
          Container(width: 1, color: context.appColors.border),
          Container(
            width: 376,
            decoration: BoxDecoration(
              color: isDark
                  ? context.appColors.sidebar
                  : context.appColors.background,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(-8, 0),
                ),
              ],
            ),
            child: const TimerPage(),
          ),
        ],
      );
    } else {
      return const TaskListView();
    }
  }

  Widget _buildFocusButton(
    TimerState timerState,
    TimerNotifier timerNotifier,
    TaskState taskState,
    bool isDark,
    bool isMobile,
  ) {
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused ||
        timerState.timerStatus == TimerStatus.completed) {
      if (timerState.timerStatus == TimerStatus.completed) {
        final isPomodoro = timerState.timerMode == TimerMode.pomodoro;
        final nextIsBreak =
            isPomodoro &&
            (timerState.timerPhase == 'break' ||
                timerState.timerPhase == 'long-break');

        // 当有多个操作按钮时，使用 Wrap 防止在窄屏手机上溢出
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (nextIsBreak)
              _buildFooterActionButton(
                icon: AppIcons.breakTime,
                label: isMobile ? '休息' : '开始休息',
                onTap: () => timerNotifier.startBreak(),
                color: context.appColors.accent,
                isPrimary: true,
              )
            else
              _buildFooterActionButton(
                icon: AppIcons.focus,
                label: isMobile ? '专注' : '开始专注',
                onTap: () => timerNotifier.resetFocus(),
                color: context.appColors.accentSecondary,
                isPrimary: true,
              ),
            _buildFooterActionButton(
              icon: AppIcons.play,
              label: isMobile ? '继续' : '继续专注',
              onTap: () => timerNotifier.startFocus(),
              color: context.appColors.accent,
              isPrimary: false,
              isDark: isDark,
            ),
          ],
        );
      }
      final remaining = timerState.totalSeconds - timerState.elapsedSeconds;
      final minutes = remaining ~/ 60;
      final seconds = remaining % 60;
      return Material(
        color: context.appColors.accentSecondary,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () =>
              _handleFooterButton(timerState, timerNotifier, taskState),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.timer, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: context.appColors.accentSecondary,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _handleFooterButton(timerState, timerNotifier, taskState),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.focus, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '开始专注',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleFooterButton(
    TimerState timerState,
    TimerNotifier timerNotifier,
    TaskState taskState,
  ) {
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused) {
      setState(() => _showTimerPanel = !_showTimerPanel);
      return;
    }

    if (_showTimerPanel) {
      if (timerState.timerStatus == TimerStatus.idle) {
        setState(() => _showTimerPanel = false);
      }
    } else {
      if (taskState.selectedTaskId == null) {
        setState(() => _showNoTaskToast = true);
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _showNoTaskToast = false);
        });
      } else {
        final task = taskState.tasks
            .where((t) => t.id == taskState.selectedTaskId)
            .firstOrNull;
        if (task != null && timerState.timerStatus == TimerStatus.idle) {
          timerNotifier.startFocus(taskTitle: task.title, taskId: task.id);
        }
        setState(() => _showTimerPanel = true);
      }
    }
  }

  Widget _buildFooterActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isPrimary,
    bool isDark = false,
  }) {
    return Material(
      color: isPrimary ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: !isPrimary
              ? BoxDecoration(
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 15, color: isPrimary ? Colors.white : color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isPrimary ? Colors.white : color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
