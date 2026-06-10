import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
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
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: '单核',
                  icon: AppIcons.focus,
                  onTap: () => _selectMode(TimerMode.singleCore),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeButton(
                  label: '番茄',
                  icon: AppIcons.timer,
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
                activeColor: context.appColors.accent,
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
                      color: context.appColors.text,
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
            Navigator.of(context, rootNavigator: true).pop();
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
    ref.read(overdueModeDialogProvider.notifier).state = 0;
    Navigator.of(context, rootNavigator: true).pop();
    // 确认选择并开始专注
    notifier.confirmOverdueMode(mode);
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.appColors.border,
            ),
          ),
          child: Column(
            children: [
              AppIcon(
                icon,
                size: 24,
                color: context.appColors.accent,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.appColors.text,
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
