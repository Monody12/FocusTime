import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';

void main() {
  group('Recurrence utils', () {
    test('monthly skip policy skips invalid month dates', () {
      final config = RecurrenceConfig(
        frequency: RecurrenceFrequency.monthly,
        monthlyMode: 'date',
        daysOfMonth: [31],
        overflowPolicy: 'skip',
      );

      final next = getNextDate(DateTime(2026, 1, 31), config);
      expect(next, DateTime(2026, 3, 31));
    });

    test('yearly skip policy skips non-leap years for Feb 29', () {
      final config = RecurrenceConfig(
        frequency: RecurrenceFrequency.yearly,
        overflowPolicy: 'skip',
      );

      final next = getNextDate(DateTime(2024, 2, 29), config);
      expect(next, DateTime(2028, 2, 29));
    });

    test('weekly custom days use DateTime weekday values', () {
      final config = RecurrenceConfig(
        frequency: RecurrenceFrequency.weekly,
        daysOfWeek: [DateTime.monday, DateTime.friday],
      );

      final next = getNextDate(DateTime(2026, 7, 7), config);
      expect(next.weekday, DateTime.friday);
    });

    test('range respects the configured end date', () {
      final config = RecurrenceConfig(
        frequency: RecurrenceFrequency.daily,
        endsAt: '2026-08-03',
      );

      final dates = getRecurrenceDatesInRange(
        config,
        '2026-08-01',
        '2026-08-01',
        '2026-08-10',
      );

      expect(dates, [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 3),
      ]);
    });

    test('range respects the remaining occurrence count', () {
      final config = RecurrenceConfig(
        frequency: RecurrenceFrequency.daily,
        endsAfterOccurrences: 2,
      );

      final dates = getRecurrenceDatesInRange(
        config,
        '2026-08-01',
        '2026-08-01',
        '2026-08-10',
      );

      expect(dates, [DateTime(2026, 8, 1), DateTime(2026, 8, 2)]);
    });

    test('invalid synced interval falls back to one', () {
      final config = RecurrenceConfig.fromJson({
        'frequency': 'daily',
        'interval': 0,
      });

      expect(config.interval, 1);
      expect(getNextDate(DateTime(2026, 8, 1), config), DateTime(2026, 8, 2));
    });
  });
}
