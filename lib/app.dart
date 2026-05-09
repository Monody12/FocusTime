import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'features/sidebar/presentation/widgets/sidebar.dart';
import 'features/timer/presentation/pages/timer_page.dart';
import 'features/tasks/presentation/pages/task_list_page.dart';
import 'features/tasks/presentation/pages/task_detail_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';
import 'features/calendar/presentation/pages/calendar_page.dart';
import 'features/ai_assistant/presentation/pages/ai_chat_page.dart';
import 'features/timer/providers/timer_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'core/providers/package_info_provider.dart';

class FocusMyTimeApp extends ConsumerStatefulWidget {
  const FocusMyTimeApp({super.key});

  @override
  ConsumerState<FocusMyTimeApp> createState() => _FocusMyTimeAppState();
}

class _FocusMyTimeAppState extends ConsumerState<FocusMyTimeApp> {
  bool _showTimerPanel = false;  // 默认不显示计时器，开始专注后才显示
  bool _showSettings = false;
  bool _showCalendar = false;
  bool _showAiChat = false;
  bool _showNoTaskToast = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    // final timerState = ref.watch(timerProvider); // Removed to prevent global rebuilds
    final timerNotifier = ref.read(timerProvider.notifier);
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final taskState = ref.watch(taskProvider);
    
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 800;
    
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    // Auto-open timer panel when transition to running
    ref.listen(timerProvider, (previous, next) {
      final wasRunning = previous?.timerStatus == TimerStatus.running;
      final isRunning = next.timerStatus == TimerStatus.running;
      if (isRunning && !wasRunning && _showTimerPanel == false) {
        setState(() => _showTimerPanel = true);
      }
    });

    // Reset task selection when list changes (Riverpod handles this, but we can listen for side effects)
    ref.listen(taskProvider, (previous, next) {
      if (previous != null && previous.currentListId != next.currentListId) {
        // List changed logic can be added here if needed
      }
    });

    Widget mainContent = Scaffold(
      key: _scaffoldKey, // For drawer access
      drawer: isMobile ? Drawer(
        width: 260,
        child: Sidebar(
          onListChanged: () {
            ref.read(taskProvider.notifier).setSelectedTask(null);
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ) : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                // Header (Top-level, spans full width)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (isMobile)
                      Builder(
                        builder: (context) => IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                    // 应用标题
                    Text(
                      'FocusMyTime',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                      ),
                    ),
                    const Spacer(),
                    // Theme toggle
                    IconButton(
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
                      onPressed: () => themeNotifier.toggleTheme(),
                      tooltip: '切换主题',
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                    const SizedBox(width: 4),
                    // AI Assistant button
                    TextButton.icon(
                      onPressed: () => setState(() => _showAiChat = true),
                      icon: const Icon(Icons.smart_toy_outlined, size: 18),
                      label: isMobile ? const Text('') : const Text('AI'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Settings button
                    TextButton.icon(
                      onPressed: () => setState(() => _showSettings = true),
                      icon: const Icon(Icons.settings, size: 18),
                      label: isMobile ? const Text('') : const Text('设置'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
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
                            ref.read(taskProvider.notifier).setSelectedTask(null);
                          },
                        ),
                      ),

                    // Main area content
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _showCalendar
                                ? const CalendarPage()
                                : _buildMainContent(isDark, isMobile),
                          ),
                          // Footer
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                              border: Border(
                                top: BorderSide(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
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
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                else
                                  Flexible(
                                    child: Consumer(
                                      builder: (context, ref, child) {
                                        final timerState = ref.watch(timerProvider);
                                        final taskState = ref.watch(taskProvider);
                                        return _buildFocusButton(timerState, timerNotifier, taskState, isDark, isMobile);
                                      },
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() => _showCalendar = !_showCalendar);
                                    if (_showCalendar) _showSettings = false;
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 10),
                                    side: BorderSide(
                                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: Text(
                                    isMobile ? '📅' : '📅 日历',
                                    style: TextStyle(
                                      color: _showCalendar
                                          ? const Color(0xFF4FC3F7)
                                          : (isDark ? AppColors.darkText : AppColors.lightText),
                                    ),
                                  ),
                                ),
                                if (!isMobile) ...[
                                  const SizedBox(width: 12),
                                  ref.watch(packageInfoProvider).when(
                                    data: (info) => Text(
                                      'v${info.version}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                      ),
                                    ),
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, _) => const SizedBox.shrink(),
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
                    if (!isMobile && taskState.selectedTaskId != null && !_showCalendar)
                      TaskDetailPage(
                        taskId: taskState.selectedTaskId!,
                        onClose: () {
                          ref.read(taskProvider.notifier).setSelectedTask(null);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

          // Task Detail overlay (Mobile only)
          if (isMobile && taskState.selectedTaskId != null && !_showCalendar)
            Positioned.fill(
              child: Container(
                color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                child: TaskDetailPage(
                  taskId: taskState.selectedTaskId!,
                  onClose: () {
                    ref.read(taskProvider.notifier).setSelectedTask(null);
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
                      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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
                      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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

    return MaterialApp(
      title: 'FocusMyTime',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            if (taskState.selectedTaskId != null) {
              final taskNotifier = ref.read(taskProvider.notifier);
              final task = taskState.tasks.where((t) => t.id == taskState.selectedTaskId).firstOrNull;
              if (task != null) {
                if (task.isMyDay) taskNotifier.removeFromMyDay(task.id);
                else taskNotifier.addToMyDay(task.id);
              }
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
            if (taskState.selectedTaskId != null) {
              ref.read(taskProvider.notifier).toggleTaskComplete(taskState.selectedTaskId!);
            }
          },
          const SingleActivator(LogicalKeyboardKey.delete): () {
            if (taskState.selectedTaskId != null) {
              final task = taskState.tasks.where((t) => t.id == taskState.selectedTaskId).firstOrNull;
              if (task != null) {
                _confirmDeleteTask(context, task);
              }
            }
          },
        },
        child: mainContent,
      ),
    );
  }

  void _confirmDeleteTask(BuildContext context, TaskItem task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除任务 "${task.title}" 吗？'),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
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

  Widget _buildMainContent(bool isDark, bool isMobile) {
    if (_showTimerPanel) {
      if (isMobile) {
        // Mobile: Show TimerPage as a stack or separate view
        return Stack(
          children: [
            TaskListView(
              onTaskSelected: (taskId) => ref.read(taskProvider.notifier).setSelectedTask(taskId),
            ),
            Positioned.fill(
              child: Container(
                color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => setState(() => _showTimerPanel = false),
                        ),
                        const Text('专注计时', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Expanded(
            child: TaskListView(
              onTaskSelected: (taskId) => ref.read(taskProvider.notifier).setSelectedTask(taskId),
            ),
          ),
          Container(
            width: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          SizedBox(
            width: 280,
            child: const TimerPage(),
          ),
        ],
      );
    } else {
      return TaskListView(
        onTaskSelected: (taskId) => ref.read(taskProvider.notifier).setSelectedTask(taskId),
      );
    }
  }

  Widget _buildFocusButton(TimerState timerState, TimerNotifier timerNotifier, TaskState taskState, bool isDark, bool isMobile) {
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused ||
        timerState.timerStatus == TimerStatus.completed) {
      if (timerState.timerStatus == TimerStatus.completed) {
        final isPomodoro = timerState.timerMode == TimerMode.pomodoro;
        final nextIsBreak = isPomodoro && (timerState.timerPhase == 'break' || timerState.timerPhase == 'long-break');

        // 当有多个操作按钮时，使用 Wrap 防止在窄屏手机上溢出
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (nextIsBreak)
              _buildFooterActionButton(
                label: isMobile ? '☕ 休息' : '☕ 开始休息',
                onTap: () => timerNotifier.startBreak(),
                color: const Color(0xFF7C3AED),
                isPrimary: true,
              )
            else
              _buildFooterActionButton(
                label: isMobile ? '🎯 专注' : '🎯 开始专注',
                onTap: () => timerNotifier.resetFocus(),
                color: const Color(0xFF4FC3F7),
                isPrimary: true,
              ),
            _buildFooterActionButton(
              label: isMobile ? '🎯 继续' : '🎯 继续专注',
              onTap: () => timerNotifier.startFocus(),
              color: const Color(0xFF7C3AED),
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
        color: const Color(0xFF4FC3F7),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => _handleFooterButton(timerState, timerNotifier, taskState),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Text(
              '⏱ ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }
    return Material(
      color: const Color(0xFF4FC3F7),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _handleFooterButton(timerState, timerNotifier, taskState),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: const Text(
            '🎯 开始专注',
            style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  void _handleFooterButton(TimerState timerState, TimerNotifier timerNotifier, TaskState taskState) {
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
        final task = taskState.tasks.where((t) => t.id == taskState.selectedTaskId).firstOrNull;
        if (task != null && timerState.timerStatus == TimerStatus.idle) {
          timerNotifier.startFocus(taskTitle: task.title, taskId: task.id);
        }
        setState(() => _showTimerPanel = true);
      }
    }
  }

  String _getFooterButtonText(TimerState timerState) {
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused ||
        timerState.timerStatus == TimerStatus.completed) {
      if (timerState.timerStatus == TimerStatus.completed) {
        return '✅ 已完成';
      }
      final remaining = timerState.totalSeconds - timerState.elapsedSeconds;
      final minutes = remaining ~/ 60;
      final seconds = remaining % 60;
      return '⏱ ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '🎯 开始专注';
  }

  Widget _buildFooterActionButton({
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isPrimary ? Colors.white : color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
