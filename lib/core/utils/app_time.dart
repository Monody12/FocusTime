import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum AppTimeZoneMode {
  system,
  beijing,
  unitedStates,
}

class AppTime {
  static const String settingKey = 'appTimeZoneMode';
  static const String defaultModeValue = 'system';
  static const String beijingLocationName = 'Asia/Shanghai';
  static const String unitedStatesLocationName = 'America/New_York';

  static bool _initialized = false;
  static AppTimeZoneMode _mode = AppTimeZoneMode.system;

  static AppTimeZoneMode get mode => _mode;

  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static void configure(AppTimeZoneMode mode) {
    initialize();
    _mode = mode;
  }

  static AppTimeZoneMode modeFromValue(String? value) {
    switch (value) {
      case 'beijing':
        return AppTimeZoneMode.beijing;
      case 'unitedStates':
        return AppTimeZoneMode.unitedStates;
      case 'system':
      default:
        return AppTimeZoneMode.system;
    }
  }

  static String valueFromMode(AppTimeZoneMode mode) {
    switch (mode) {
      case AppTimeZoneMode.beijing:
        return 'beijing';
      case AppTimeZoneMode.unitedStates:
        return 'unitedStates';
      case AppTimeZoneMode.system:
        return 'system';
    }
  }

  static String label(AppTimeZoneMode mode) {
    switch (mode) {
      case AppTimeZoneMode.beijing:
        return '北京';
      case AppTimeZoneMode.unitedStates:
        return '美国';
      case AppTimeZoneMode.system:
        return '跟随系统';
    }
  }

  static String description(AppTimeZoneMode mode) {
    switch (mode) {
      case AppTimeZoneMode.beijing:
        return '北京时区 ${offsetLabelForMode(mode)}';
      case AppTimeZoneMode.unitedStates:
        return '美国东部时区 ${offsetLabelForMode(mode)}';
      case AppTimeZoneMode.system:
        return '当前系统时区 ${offsetLabelForMode(mode)}';
    }
  }

  static DateTime now() =>
      fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch);

  static DateTime fromMillisecondsSinceEpoch(int milliseconds) {
    initialize();
    if (_mode == AppTimeZoneMode.system) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
        _locationForMode(_mode), milliseconds);
  }

  static DateTime create(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
  ]) {
    initialize();
    if (_mode == AppTimeZoneMode.system) {
      return DateTime(
          year, month, day, hour, minute, second, millisecond, microsecond);
    }
    return tz.TZDateTime(
      _locationForMode(_mode),
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
  }

  static DateTime? parseSelectedDateTime(String date, String time) {
    try {
      final dateParts = date.split('-');
      final timeParts = time.split(':');
      return create(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? parseSelectedIso(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final hasExplicitOffset = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(value);
    if (hasExplicitOffset) {
      return fromMillisecondsSinceEpoch(parsed.millisecondsSinceEpoch);
    }
    return create(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }

  static String formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  static String formatDateTime(DateTime date) =>
      '${formatDate(date)} ${formatTime(date)}';

  static String formatDateTimeFromMilliseconds(int milliseconds) =>
      formatDateTime(fromMillisecondsSinceEpoch(milliseconds));

  static int startOfDateMilliseconds(String date) {
    final parts = date.split('-');
    return create(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).millisecondsSinceEpoch;
  }

  static int endOfDateMilliseconds(String date) {
    final parts = date.split('-');
    return create(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]) + 1,
    ).subtract(const Duration(milliseconds: 1)).millisecondsSinceEpoch;
  }

  static tz.Location notificationLocation() {
    initialize();
    return _locationForMode(_mode);
  }

  static String offsetLabelForMode(AppTimeZoneMode mode) {
    final date = _dateForMode(mode);
    return _formatOffset(date.timeZoneOffset);
  }

  static DateTime _dateForMode(AppTimeZoneMode mode) {
    initialize();
    final milliseconds = DateTime.now().millisecondsSinceEpoch;
    if (mode == AppTimeZoneMode.system) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
        _locationForMode(mode), milliseconds);
  }

  static tz.Location _locationForMode(AppTimeZoneMode mode) {
    switch (mode) {
      case AppTimeZoneMode.beijing:
        return tz.getLocation(beijingLocationName);
      case AppTimeZoneMode.unitedStates:
        return tz.getLocation(unitedStatesLocationName);
      case AppTimeZoneMode.system:
        return tz.local;
    }
  }

  static String _formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hours = abs.inHours.toString().padLeft(2, '0');
    final minutes = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }
}
