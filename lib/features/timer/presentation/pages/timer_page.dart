import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/timer/presentation/widgets/timer_display.dart';
import 'package:focus_my_time/features/timer/presentation/widgets/timer_controls.dart';
import 'package:focus_my_time/features/timer/presentation/widgets/mode_selector.dart';
import 'package:focus_my_time/features/timer/presentation/widgets/overdue_mode_dialog.dart';

class TimerPage extends ConsumerWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(timerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 监听超时模式对话框触发
    ref.listen(overdueModeDialogProvider, (_, timestamp) {
      if (timestamp > 0) {
        showOverdueModeDialog(context, ref);
      }
    });

    final isInBreakPhase = timerState.timerMode == TimerMode.pomodoro &&
        (timerState.timerPhase == 'break' ||
            timerState.timerPhase == 'long-break');

    // Bug 修复：两个完成面板条件之前几乎相同，导致同时显示。
    // 现在分开判断：
    //   - focusDone: 专注阶段结束，等待用户开始休息
    //   - breakDone: 休息阶段结束，等待用户开始下一轮专注
    final isCompleted = timerState.timerStatus == TimerStatus.completed;
    final focusDone = isCompleted &&
        timerState.timerMode == TimerMode.pomodoro &&
        (timerState.timerPhase == 'break' ||
            timerState.timerPhase == 'long-break') &&
        !timerState.pomodoroConfig.autoStartBreak;
    final breakDone = isCompleted &&
        isInBreakPhase &&
        !timerState.pomodoroConfig.autoStartNext;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 LayoutBuilder 获知实际可用宽度，防止内容溢出
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            // 确保内容宽度不超过父容器宽度
            constraints:
                BoxConstraints(minWidth: 0, maxWidth: constraints.maxWidth),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.appColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 模式选择器
                  const ModeSelector(),
                  const SizedBox(height: 20),

                  // 当前任务名称
                  if (timerState.currentTask.isNotEmpty &&
                      timerState.timerPhase == 'focus')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        timerState.currentTask,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.text,
                        ),
                      ),
                    ),

                  // 计时器圆环
                  const Center(child: TimerDisplay()),
                  const SizedBox(height: 12),

                  // 阶段/循环信息
                  if (timerState.timerMode == TimerMode.singleCore &&
                      timerState.targetTime != null)
                    _buildSingleCoreInfo(context, timerState)
                  else if (timerState.timerMode == TimerMode.pomodoro)
                    _buildPomodoroInfo(context, timerState)
                  else if (timerState.timerMode == TimerMode.task)
                    _buildTaskInfo(context, timerState),

                  const SizedBox(height: 16),

                  // 专注完成面板（等待用户点击开始休息）
                  if (focusDone) ...[
                    _buildFocusCompletePanel(context, ref, timerState),
                    const SizedBox(height: 8),
                  ],

                  // 休息完成面板（等待用户点击开始专注）
                  if (breakDone) ...[
                    _buildBreakCompletePanel(context, ref, timerState),
                    const SizedBox(height: 8),
                  ],

                  // 计时器控制按钮（开始/暂停/重置）
                  const TimerControls(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleCoreInfo(BuildContext context, TimerState timerState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      // Wrap 自动换行，防止长文本溢出
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          Text(
            '目标时间：${_formatTargetTime(timerState.targetTime!)}',
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.text,
            ),
          ),
          Text(
            '最少 ${timerState.singleCoreConfig.minDuration} 分钟',
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPomodoroInfo(BuildContext context, TimerState timerState) {
    String phaseText;
    if (timerState.timerPhase == 'focus') {
      phaseText = '专注 ${timerState.pomodoroConfig.focusDuration} 分钟';
    } else if (timerState.timerPhase == 'break') {
      phaseText = '短休息 ${timerState.pomodoroConfig.breakDuration} 分钟';
    } else {
      phaseText = '长休息 ${timerState.pomodoroConfig.longBreakDuration} 分钟';
    }

    String cycleText = '';
    if (timerState.pomodoroConfig.enableCycle) {
      cycleText = '第 ${timerState.currentCycle + 1} 轮';
      if (!timerState.pomodoroConfig.autoStartBreak) cycleText += ' · 手动';
      cycleText += ' · ${timerState.pomodoroConfig.cyclesBeforeLongBreak}轮长休息';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          Text(
            phaseText,
            style: TextStyle(fontSize: 13, color: context.appColors.text),
          ),
          if (cycleText.isNotEmpty)
            Text(
              cycleText,
              style: TextStyle(
                  fontSize: 12, color: context.appColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskInfo(BuildContext context, TimerState timerState) {
    final remaining = timerState.remainingSeconds ~/ 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          Text(
            '任务模式 · 剩余 $remaining 分钟',
            style: TextStyle(fontSize: 13, color: context.appColors.text),
          ),
        ],
      ),
    );
  }

  /// 休息结束面板：点击"开始专注"或"跳过"
  Widget _buildBreakCompletePanel(
      BuildContext context, WidgetRef ref, TimerState timerState) {
    final timerNotifier = ref.read(timerProvider.notifier);
    final phaseName = timerState.timerPhase == 'long-break' ? '长休息' : '短休息';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        children: [
          Text(
            '$phaseName完成！点击开始专注',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.text,
            ),
          ),
          const SizedBox(height: 10),
          // 按钮横向排列，使用 Expanded 让按钮等分宽度而不溢出
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => timerNotifier.startFocus(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('开始专注', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => timerNotifier.skipBreak(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('跳过', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 专注结束面板：点击"开始休息"
  Widget _buildFocusCompletePanel(
      BuildContext context, WidgetRef ref, TimerState timerState) {
    final timerNotifier = ref.read(timerProvider.notifier);
    final breakName = timerState.timerPhase == 'long-break' ? '长' : '短';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        children: [
          Text(
            '专注完成！开始${breakName}休息',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => timerNotifier.startBreak(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('开始休息', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => timerNotifier.startFocus(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('继续专注', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTargetTime(DateTime targetTime) {
    final hour = targetTime.hour.toString().padLeft(2, '0');
    final minute = targetTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
