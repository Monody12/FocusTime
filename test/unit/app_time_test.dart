import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/core/utils/app_time.dart';

void main() {
  tearDown(() {
    AppTime.configure(AppTimeZoneMode.system);
  });

  group('AppTime', () {
    test('formats Beijing time from absolute timestamp', () {
      AppTime.configure(AppTimeZoneMode.beijing);

      final date = AppTime.fromMillisecondsSinceEpoch(
        DateTime.utc(2026, 1, 1, 0).millisecondsSinceEpoch,
      );

      expect(AppTime.formatDateTime(date), '2026-01-01 08:00');
      expect(AppTime.offsetLabelForMode(AppTimeZoneMode.beijing), 'UTC+08:00');
    });

    test('creates United States Eastern time as an absolute timestamp', () {
      AppTime.configure(AppTimeZoneMode.unitedStates);

      final date = AppTime.create(2026, 1, 1, 9, 30);
      final utcDate = DateTime.fromMillisecondsSinceEpoch(
        date.millisecondsSinceEpoch,
        isUtc: true,
      );

      expect(utcDate.hour, 14);
      expect(utcDate.minute, 30);
      expect(AppTime.formatTime(date), '09:30');
    });
  });
}
