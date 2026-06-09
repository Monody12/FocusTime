import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';

class OverdueModeDialog extends ConsumerStatefulWidget {
  const OverdueModeDialog({super.key});

  @override
  ConsumerState<OverdueModeDialog> createState() => _OverdueModeDialogState();
}

class _OverdueModeDialogState extends ConsumerState<OverdueModeDialog> {
  bool _rememberChoice = false;

  @override
  void initState() {
    super.initState();
    _rememberChoice = ref.read(timerProvider).rememberModeChoice;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('任务已超时'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '该任务已累计超过预期专注时间。请选择专注模式：',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: '单核',
                  emoji: '🎯',
                  onTap: () => _selectMode(TimerMode.singleCore),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeButton(
                  label: '番茄',
                  emoji: '🍅',
                  onTap: () => _selectMode(TimerMode.pomodoro),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _rememberChoice,
                onChanged: (value) {
                  setState(() => _rememberChoice = value ?? false);
                },
                activeColor:
                    isDark ? AppColors.darkAccent : AppColors.lightAccent,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _rememberChoice = !_rememberChoice);
                  },
                  child: Text(
                    '记住选择',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(overdueModeDialogProvider.notifier).state = 0;
          },
          child: const Text('取消'),
        ),
      ],
    );
  }

  void _selectMode(TimerMode mode) {
    // 保存记住选择
    final notifier = ref.read(timerProvider.notifier);
    if (_rememberChoice) {
      notifier.setRememberModeChoice(true);
      notifier.setPreferredModeWhenOverdue(mode.name);
    }
    // 确认选择并开始专注
    notifier.confirmOverdueMode(mode);
    ref.read(overdueModeDialogProvider.notifier).state = 0;
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final String emoji;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 显示超时模式选择对话框
void showOverdueModeDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const OverdueModeDialog(),
  );
}
