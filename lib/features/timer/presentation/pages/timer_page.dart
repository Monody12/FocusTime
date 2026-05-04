import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/timer_provider.dart';
import '../widgets/timer_display.dart';
import '../widgets/timer_controls.dart';
import '../widgets/mode_selector.dart';
import '../widgets/task_input.dart';
import '../../../tasks/providers/task_provider.dart';

class TimerPage extends ConsumerWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isInBreakPhase = timerState.timerMode == TimerMode.pomodoro &&
        (timerState.timerPhase == 'break' || timerState.timerPhase == 'long-break');
    final isBreakCompleted = timerState.timerStatus == TimerStatus.completed && isInBreakPhase;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Mode Selector
          const ModeSelector(),
          const SizedBox(height: 24),

          // Timer Display
          const TimerDisplay(),
          const SizedBox(height: 16),

          // Timer Info
          if (timerState.timerMode == TimerMode.singleCore && timerState.targetTime != null)
            _buildSingleCoreInfo(timerState, isDark)
          else if (timerState.timerMode == TimerMode.pomodoro)
            _buildPomodoroInfo(timerState, isDark),

          const SizedBox(height: 24),

          // Break completion panel
          if (isBreakCompleted)
            _buildBreakCompletePanel(context, ref, timerState),

          // Focus completion panel (waiting for user to start break)
          if (timerState.timerStatus == TimerStatus.completed &&
              timerState.timerMode == TimerMode.pomodoro &&
              (timerState.timerPhase == 'break' || timerState.timerPhase == 'long-break'))
            _buildFocusCompletePanel(context, ref, timerState),

          const SizedBox(height: 16),

          // Timer Controls
          const TimerControls(),
        ],
      ),
    );
  }

  Widget _buildSingleCoreInfo(TimerState timerState, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          Text(
            '目标时间：${_formatTargetTime(timerState.targetTime!)}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          Text(
            '最少 ${timerState.singleCoreConfig.minDuration} 分钟',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPomodoroInfo(TimerState timerState, bool isDark) {
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
      cycleText = ' · 第 ${timerState.currentCycle + 1} 轮';
      if (!timerState.pomodoroConfig.autoStartBreak) {
        cycleText += ' · 手动模式';
      }
      cycleText += ' · ${timerState.pomodoroConfig.cyclesBeforeLongBreak}轮长休息';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          Text(
            phaseText,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          if (cycleText.isNotEmpty)
            Text(
              cycleText,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreakCompletePanel(BuildContext context, WidgetRef ref, TimerState timerState) {
    final timerNotifier = ref.read(timerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        children: [
          Text(
            '${timerState.timerPhase == 'long-break' ? '长休息' : '短休息'}完成！'
            '${timerState.pomodoroConfig.autoStartNext ? ' 自动开始下一轮...' : ' 点击开始专注'}',
            style: TextStyle(
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          if (!timerState.pomodoroConfig.autoStartNext) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => timerNotifier.startFocus(),
                  child: const Text('开始专注'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => timerNotifier.skipBreak(),
                  child: const Text('跳过休息'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusCompletePanel(BuildContext context, WidgetRef ref, TimerState timerState) {
    final timerNotifier = ref.read(timerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        children: [
          Text(
            '专注完成！开始${timerState.timerPhase == 'long-break' ? '长' : '短'}休息',
            style: TextStyle(
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          if (timerState.pomodoroConfig.autoStartBreak)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '（自动模式）',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => timerNotifier.startBreak(),
              child: const Text('开始休息'),
            ),
          ],
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