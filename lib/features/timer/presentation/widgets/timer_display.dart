import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/timer_provider.dart';

class TimerDisplay extends ConsumerWidget {
  const TimerDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(timerProvider);
    final size = 160.0;
    const strokeWidth = 8.0;
    final radius = (size - strokeWidth) / 2;
    final circumference = radius * 2 * 3.14159;
    final offset = circumference * (1 - timerState.progress);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progressColor = timerState.timerStatus == TimerStatus.completed
        ? (isDark ? const Color(0xFF10B981) : const Color(0xFF10B981))
        : (isDark ? const Color(0xFF7C3AED) : const Color(0xFF7C3AED));
    final borderColor = isDark ? const Color(0xFF3D3D5C) : const Color(0xFFE5E7EB);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          CustomPaint(
            size: Size(size, size),
            painter: CircleProgressPainter(
              progress: 1.0,
              color: borderColor,
              strokeWidth: strokeWidth,
            ),
          ),
          // Progress circle
          CustomPaint(
            size: Size(size, size),
            painter: CircleProgressPainter(
              progress: timerState.progress,
              color: progressColor,
              strokeWidth: strokeWidth,
            ),
          ),
          // Time text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timerState.formattedTime,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: timerState.timerStatus == TimerStatus.completed
                      ? progressColor
                      : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF1F2937)),
                ),
              ),
              if (timerState.timerStatus == TimerStatus.completed)
                Text(
                  '完成！',
                  style: TextStyle(
                    fontSize: 14,
                    color: progressColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  CircleProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // Start from top
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
