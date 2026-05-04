import 'package:flutter_test/flutter_test.dart';
import 'package:focus_timer/core/utils/time_utils.dart';

void main() {
  group('formatTime', () {
    test('formats zero correctly', () {
      expect(formatTime(0), '00:00');
    });

    test('formats seconds only', () {
      expect(formatTime(45), '00:45');
    });

    test('formats minutes and seconds', () {
      expect(formatTime(90), '01:30');
    });

    test('formats 25 minutes correctly', () {
      expect(formatTime(1500), '25:00');
    });

    test('pads single digit minutes', () {
      expect(formatTime(65), '01:05');
    });

    test('pads single digit seconds', () {
      expect(formatTime(5), '00:05');
    });
  });

  group('calculateSingleCoreTarget', () {
    test('returns minimum 25 minutes when current time is near hour', () {
      final result = calculateSingleCoreTarget(25);
      expect(result.durationMinutes, greaterThanOrEqualTo(25));
    });

    test('targetTime is in the future', () {
      final now = DateTime.now();
      final result = calculateSingleCoreTarget(25);
      expect(result.targetTime.isAfter(now), true);
    });

    test('durationMinutes respects minDuration parameter', () {
      // Test with different minDurations
      final result30 = calculateSingleCoreTarget(30);
      final result45 = calculateSingleCoreTarget(45);

      // Both should be at least their respective minDuration
      expect(result30.durationMinutes, greaterThanOrEqualTo(30));
      expect(result45.durationMinutes, greaterThanOrEqualTo(45));
    });
  });

  group('formatDate', () {
    test('formats date correctly', () {
      final date = DateTime(2024, 1, 15);
      expect(formatDate(date), '2024-01-15');
    });

    test('pads single digit month', () {
      final date = DateTime(2024, 5, 5);
      expect(formatDate(date), '2024-05-05');
    });

    test('pads single digit day', () {
      final date = DateTime(2024, 12, 9);
      expect(formatDate(date), '2024-12-09');
    });
  });

  group('formatTimeOfDay', () {
    test('formats time correctly', () {
      final date = DateTime(2024, 1, 15, 14, 30);
      expect(formatTimeOfDay(date), '14:30');
    });

    test('pads single digit hour', () {
      final date = DateTime(2024, 1, 15, 9, 5);
      expect(formatTimeOfDay(date), '09:05');
    });

    test('formats midnight correctly', () {
      final date = DateTime(2024, 1, 15, 0, 0);
      expect(formatTimeOfDay(date), '00:00');
    });
  });
}