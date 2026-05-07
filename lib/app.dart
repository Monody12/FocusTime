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
import 'features/timer/providers/timer_provider.dart';
import 'features/tasks/providers/task_provider.dart';

class FocusMyTimeApp extends ConsumerStatefulWidget {
  const FocusMyTimeApp({super.key});

  @override
  ConsumerState<FocusMyTimeApp> createState() => _FocusMyTimeAppState();
}

class _FocusMyTimeAppState extends ConsumerState<FocusMyTimeApp> {
  bool _showTimerPanel = false;  // 默认不显示计时器，开始专注后才显示
  bool _showSettings = false;
  bool _showCalendar = false;
  String? _selectedTaskId;
  bool _showNoTaskToast = false;
  String? _lastListId; // Track last list to detect list changes

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
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

    // Reset task selection when list changes
    ref.listen(taskProvider, (previous, next) {
      if (previous != null && previous.currentListId != next.currentListId) {
        setState(() {
          _selectedTaskId = null;
          _lastListId = next.currentListId;
        });
        // Also tell task provider to clear selection
        ref.read(taskProvider.notifier).setSelectedTask(null);
      }
    });

    return MaterialApp(
      title: 'FocusMyTime',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            if (_selectedTaskId != null) {
              final taskNotifier = ref.read(taskProvider.notifier);
              final task = ref.read(taskProvider).tasks.where((t) => t.id == _selectedTaskId).firstOrNull;
              if (task != null) {
                if (task.isMyDay) taskNotifier.removeFromMyDay(task.id);
                else taskNotifier.addToMyDay(task.id);
              }
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
            if (_selectedTaskId != null) {
              ref.read(taskProvider.notifier).toggleTaskComplete(_selectedTaskId!);
            }
          },
          const SingleActivator(LogicalKeyboardKey.delete): () {
            if (_selectedTaskId != null) {
              final task = ref.read(taskProvider).tasks.where((t) => t.id == _selectedTaskId).firstOrNull;
              if (task != null) {
                _confirmDeleteTask(context, task);
              }
            }
          },
        },
        child: Scaffold(
          body: Stack(
          children: [
            Row(
              children: [
                // Sidebar (220px fixed)
                SizedBox(
                  width: 220,
                  child: Sidebar(
                    onListChanged: () {
                      setState(() {
                        _selectedTaskId = null;
                      });
                      ref.read(taskProvider.notifier).setSelectedTask(null);
                    },
                  ),
                ),

                // Main content area
                Expanded(
                  child: Column(
                    children: [
                      // Header
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
                            Text(
                              'Focus Tasks',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                              ),
                            ),
                            const Spacer(),
                            // Theme toggle button
                            IconButton(
                              icon: Icon(
                                isDark ? Icons.light_mode : Icons.dark_mode,
                                size: 20,
                              ),
                              onPressed: () => themeNotifier.toggleTheme(),
                              tooltip: '切换主题',
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                            const SizedBox(width: 8),
                            // Settings button
                            TextButton.icon(
                              onPressed: () => setState(() => _showSettings = true),
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('设置'),
                              style: TextButton.styleFrom(
                                foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Main area
                      Expanded(
                        child: _showCalendar
                            ? const CalendarPage()
                            : _buildMainContent(isDark),
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
                            // No task toast
                            if (_showNoTaskToast)
                              Expanded(
                                child: Text(
                                  '⚠ 请先选择一个任务',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                              )
                            else
                              _buildFocusButton(timerState, timerNotifier, isDark),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () {
                                setState(() => _showCalendar = !_showCalendar);
                                if (_showCalendar) _showSettings = false;
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                side: BorderSide(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                '📅 日历',
                                style: TextStyle(
                                  color: _showCalendar
                                      ? const Color(0xFF4FC3F7)
                                      : (isDark ? AppColors.darkText : AppColors.lightText),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'v1.0.1',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Task Detail panel (right side, as sibling to main content)
                if (_selectedTaskId != null && !_showCalendar)
                  SizedBox(
                    width: 320,
                    child: TaskDetailPage(
                      taskId: _selectedTaskId!,
                      onClose: () {
                        setState(() => _selectedTaskId = null);
                        ref.read(taskProvider.notifier).setSelectedTask(null);
                      },
                    ),
                  ),
              ],
            ),

            // Settings overlay (full screen modal)
            if (_showSettings)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    width: 500,
                    height: MediaQuery.of(context).size.height * 0.8,
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
          ],
        ),
      ),
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
              setState(() => _selectedTaskId = null);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);

    if (_showTimerPanel) {
      // Grid layout: task list (left, flex:1) + timer (right, 280px)
      return Row(
        children: [
          // Task list (left)
          Expanded(
            child: TaskListView(
              onTaskSelected: (taskId) {
                setState(() => _selectedTaskId = taskId);
              },
            ),
          ),
          // Divider
          Container(
            width: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          // 计时器面板（右侧，固定 280px 宽）
          SizedBox(
            width: 280,
            child: const TimerPage(),
          ),
        ],
      );
    } else {
      // Just task list
      return TaskListView(
        onTaskSelected: (taskId) {
          setState(() => _selectedTaskId = taskId);
        },
      );
    }
  }

  Widget _buildFocusButton(TimerState timerState, TimerNotifier timerNotifier, bool isDark) {
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused ||
        timerState.timerStatus == TimerStatus.completed) {
      if (timerState.timerStatus == TimerStatus.completed) {
        final isPomodoro = timerState.timerMode == TimerMode.pomodoro;
        final nextIsBreak = isPomodoro && (timerState.timerPhase == 'break' || timerState.timerPhase == 'long-break');

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (nextIsBreak)
              _buildFooterActionButton(
                label: '☕ 开始休息',
                onTap: () => timerNotifier.startBreak(),
                color: const Color(0xFF7C3AED),
                isPrimary: true,
              )
            else
              _buildFooterActionButton(
                label: '🎯 开始专注',
                onTap: () => timerNotifier.resetFocus(),
                color: const Color(0xFF4FC3F7),
                isPrimary: true,
              ),
            const SizedBox(width: 8),
            _buildFooterActionButton(
              label: '🎯 继续专注',
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
          onTap: () => _handleFooterButton(timerState, timerNotifier),
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
        onTap: () => _handleFooterButton(timerState, timerNotifier),
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

  void _handleFooterButton(TimerState timerState, TimerNotifier timerNotifier) {
    // 计时运行时，点击按钮切换计时面板显示/隐藏
    if (timerState.timerStatus == TimerStatus.running ||
        timerState.timerStatus == TimerStatus.paused) {
      setState(() => _showTimerPanel = !_showTimerPanel);
      return;
    }

    // 非运行状态
    if (_showTimerPanel) {
      // 如果计时面板已显示且没有在计时，隐藏面板
      if (timerState.timerStatus == TimerStatus.idle) {
        setState(() => _showTimerPanel = false);
      }
    } else {
      if (_selectedTaskId == null) {
        setState(() => _showNoTaskToast = true);
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _showNoTaskToast = false);
        });
      } else {
        final taskState = ref.read(taskProvider);
        final task = taskState.tasks.where((t) => t.id == _selectedTaskId).firstOrNull;
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
