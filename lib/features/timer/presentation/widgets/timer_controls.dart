import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/timer_provider.dart';

class TimerControls extends ConsumerWidget {
  const TimerControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);

    // 紧凑布局：计时器面板宽度有限(280px)，使用较小的按钮和间距
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 开始/暂停按钮
        ElevatedButton(
          onPressed: () {
            if (timerState.timerStatus == TimerStatus.running) {
              timerNotifier.pauseFocus();
            } else if (timerState.timerStatus == TimerStatus.paused) {
              timerNotifier.resumeFocus();
            } else {
              timerNotifier.startFocus();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                timerState.timerStatus == TimerStatus.running
                    ? Icons.pause
                    : Icons.play_arrow,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                timerState.timerStatus == TimerStatus.running
                    ? '暂停'
                    : timerState.timerStatus == TimerStatus.paused
                        ? '继续'
                        : '开始',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 重置按钮
        OutlinedButton(
          onPressed: timerState.timerStatus == TimerStatus.idle
              ? null
              : () => timerNotifier.resetFocus(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(
              color: timerState.timerStatus == TimerStatus.idle
                  ? Colors.grey.withValues(alpha: 0.3)
                  : const Color(0xFF7C3AED),
            ),
            foregroundColor: const Color(0xFF7C3AED),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 6),
              Text('重置', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
