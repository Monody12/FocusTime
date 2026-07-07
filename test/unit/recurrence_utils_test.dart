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
  });
}
