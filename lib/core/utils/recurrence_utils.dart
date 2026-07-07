enum RecurrenceFrequency { daily, weekly, monthly, yearly }

class RecurrenceConfig {
  final RecurrenceFrequency frequency;
  final int interval;
  final List<int>? daysOfWeek;
  final List<int>? daysOfMonth;
  final int? dayOfMonth;
  final int? weekOrdinal;
  final int? weekDay;
  final String? monthlyMode;
  final String? weekDayGroup;
  final int? monthOfYear;
  final String? endsAt;
  final int? endsAfterOccurrences;
  final String overflowPolicy;

  RecurrenceConfig({
    required this.frequency,
    this.interval = 1,
    this.daysOfWeek,
    this.daysOfMonth,
    this.dayOfMonth,
    this.weekOrdinal,
    this.weekDay,
    this.monthlyMode,
    this.weekDayGroup,
    this.monthOfYear,
    this.endsAt,
    this.endsAfterOccurrences,
    this.overflowPolicy = 'lastDay',
  });

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
        if (daysOfMonth != null) 'daysOfMonth': daysOfMonth,
        if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
        if (weekOrdinal != null) 'weekOrdinal': weekOrdinal,
        if (weekDay != null) 'weekDay': weekDay,
        if (monthlyMode != null) 'monthlyMode': monthlyMode,
        if (weekDayGroup != null) 'weekDayGroup': weekDayGroup,
        if (monthOfYear != null) 'monthOfYear': monthOfYear,
        if (endsAt != null) 'endsAt': endsAt,
        if (endsAfterOccurrences != null)
          'endsAfterOccurrences': endsAfterOccurrences,
        'overflowPolicy': overflowPolicy,
      };

  factory RecurrenceConfig.fromJson(Map<String, dynamic> json) {
    return RecurrenceConfig(
      frequency: RecurrenceFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
        orElse: () => RecurrenceFrequency.daily,
      ),
      interval: json['interval'] ?? 1,
      daysOfWeek: json['daysOfWeek'] != null
          ? List<int>.from(json['daysOfWeek'])
          : null,
      daysOfMonth: json['daysOfMonth'] != null
          ? List<int>.from(json['daysOfMonth'])
          : null,
      dayOfMonth: json['dayOfMonth'],
      weekOrdinal: json['weekOrdinal'],
      weekDay: json['weekDay'],
      monthlyMode: json['monthlyMode'],
      weekDayGroup: json['weekDayGroup'],
      monthOfYear: json['monthOfYear'],
      endsAt: json['endsAt'],
      endsAfterOccurrences: json['endsAfterOccurrences'],
      overflowPolicy: json['overflowPolicy'] ?? 'lastDay',
    );
  }

  RecurrenceConfig copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    List<int>? daysOfWeek,
    List<int>? daysOfMonth,
    int? dayOfMonth,
    int? weekOrdinal,
    int? weekDay,
    String? monthlyMode,
    String? weekDayGroup,
    int? monthOfYear,
    String? endsAt,
    int? endsAfterOccurrences,
    String? overflowPolicy,
  }) {
    return RecurrenceConfig(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      daysOfMonth: daysOfMonth ?? this.daysOfMonth,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      weekOrdinal: weekOrdinal ?? this.weekOrdinal,
      weekDay: weekDay ?? this.weekDay,
      monthlyMode: monthlyMode ?? this.monthlyMode,
      weekDayGroup: weekDayGroup ?? this.weekDayGroup,
      monthOfYear: monthOfYear ?? this.monthOfYear,
      endsAt: endsAt ?? this.endsAt,
      endsAfterOccurrences: endsAfterOccurrences ?? this.endsAfterOccurrences,
      overflowPolicy: overflowPolicy ?? this.overflowPolicy,
    );
  }
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _dateWithOverflow(
  int year,
  int month,
  int day,
  RecurrenceConfig config,
) {
  final daysInMonth = _daysInMonth(year, month);
  if (day <= daysInMonth) return DateTime(year, month, day);
  return DateTime(year, month, daysInMonth);
}

DateTime _nextMonthlyDateWithOverflow(
  DateTime from,
  List<int> sortedDays,
  RecurrenceConfig config,
) {
  var target = DateTime(from.year, from.month + config.interval);
  for (var i = 0; i < 240; i++) {
    for (final day in sortedDays) {
      if (day <= _daysInMonth(target.year, target.month)) {
        return DateTime(target.year, target.month, day);
      }
    }
    if (config.overflowPolicy != 'skip') {
      return _dateWithOverflow(
          target.year, target.month, sortedDays.first, config);
    }
    target = DateTime(target.year, target.month + config.interval);
  }
  return _dateWithOverflow(target.year, target.month, sortedDays.first, config);
}

DateTime _nextYearlyDateWithOverflow(
  DateTime current,
  RecurrenceConfig config,
) {
  var targetYear = current.year + config.interval;
  for (var i = 0; i < 80; i++) {
    if (current.day <= _daysInMonth(targetYear, current.month)) {
      return DateTime(targetYear, current.month, current.day);
    }
    if (config.overflowPolicy != 'skip') {
      return _dateWithOverflow(targetYear, current.month, current.day, config);
    }
    targetYear += config.interval;
  }
  return _dateWithOverflow(targetYear, current.month, current.day, config);
}

List<int> _weekDaysForGroup(RecurrenceConfig config) {
  if (config.weekDayGroup == 'weekdays') return [1, 2, 3, 4, 5];
  if (config.weekDayGroup == 'weekend') return [6, 7];
  if (config.weekDayGroup == 'all') return [1, 2, 3, 4, 5, 6, 7];
  return [config.weekDay ?? 1];
}

DateTime? _nthWeekdayOfMonth(
  int year,
  int month,
  int ordinal,
  List<int> weekdays,
) {
  final dates = <DateTime>[];
  final days = _daysInMonth(year, month);
  for (var day = 1; day <= days; day++) {
    final date = DateTime(year, month, day);
    if (weekdays.contains(date.weekday)) dates.add(date);
  }
  if (dates.isEmpty) return null;
  if (ordinal == -1) return dates.last;
  final index = ordinal - 1;
  if (index < 0 || index >= dates.length) return null;
  return dates[index];
}

List<DateTime> getRecurrenceDatesInRange(
  RecurrenceConfig config,
  String anchorDate,
  String startStr,
  String endStr,
) {
  final dates = <DateTime>[];
  final start = DateTime.parse(startStr);
  final end = DateTime.parse(endStr);
  var current = DateTime.parse(anchorDate);

  // 如果开始日期在锚点之前，从锚点开始
  if (current.isBefore(start)) {
    current = getNextDate(current, config);
  }

  while (!current.isAfter(end)) {
    if (!current.isBefore(start)) {
      dates.add(current);
    }
    current = getNextDate(current, config);
  }

  return dates;
}

DateTime getNextDate(DateTime current, RecurrenceConfig config) {
  switch (config.frequency) {
    case RecurrenceFrequency.daily:
      return current.add(Duration(days: config.interval));
    case RecurrenceFrequency.weekly:
      if (config.daysOfWeek != null && config.daysOfWeek!.isNotEmpty) {
        var next = current.add(const Duration(days: 1));
        final anchorWeek =
            current.subtract(Duration(days: current.weekday - 1));
        for (var count = 0; count < 7 * config.interval + 7; count++) {
          final nextWeek = next.subtract(Duration(days: next.weekday - 1));
          final weekDistance = nextWeek.difference(anchorWeek).inDays ~/ 7;
          final weekAllowed = weekDistance % config.interval == 0;
          if (weekAllowed && config.daysOfWeek!.contains(next.weekday)) {
            return next;
          }
          next = next.add(const Duration(days: 1));
        }
        return next;
      }
      return current.add(Duration(days: 7 * config.interval));
    case RecurrenceFrequency.monthly:
      if (config.monthlyMode == 'weekday' && config.weekOrdinal != null) {
        var monthCursor =
            DateTime(current.year, current.month + config.interval);
        for (var i = 0; i < 24; i++) {
          final next = _nthWeekdayOfMonth(
            monthCursor.year,
            monthCursor.month,
            config.weekOrdinal!,
            _weekDaysForGroup(config),
          );
          if (next != null) return next;
          monthCursor =
              DateTime(monthCursor.year, monthCursor.month + config.interval);
        }
      }
      final days = config.daysOfMonth ?? [config.dayOfMonth ?? current.day];
      final sortedDays = [...days]..sort();
      for (final day in sortedDays) {
        if (day > current.day) {
          final candidate =
              _dateWithOverflow(current.year, current.month, day, config);
          if (candidate.month == current.month && candidate.isAfter(current)) {
            return candidate;
          }
        }
      }
      return _nextMonthlyDateWithOverflow(current, sortedDays, config);
    case RecurrenceFrequency.yearly:
      return _nextYearlyDateWithOverflow(current, config);
  }
}

DateTime getNextDateOnOrAfter(
  DateTime current,
  RecurrenceConfig config,
  DateTime minimumDate,
) {
  final minimumDay =
      DateTime(minimumDate.year, minimumDate.month, minimumDate.day);
  var next = getNextDate(current, config);

  // 防御性上限，避免异常配置造成无限循环。
  for (var i = 0; i < 10000; i++) {
    final nextDay = DateTime(next.year, next.month, next.day);
    if (!nextDay.isBefore(minimumDay)) return next;
    next = getNextDate(next, config);
  }

  return next;
}

String getRecurrenceSummary(RecurrenceConfig config) {
  switch (config.frequency) {
    case RecurrenceFrequency.daily:
      if (config.interval == 1) {
        return '每天';
      }
      return '每${config.interval}天';
    case RecurrenceFrequency.weekly:
      final days = config.daysOfWeek;
      final suffix = days == null || days.isEmpty
          ? ''
          : '（${days.map(_weekdayLabel).join('、')}）';
      return config.interval == 1 ? '每周$suffix' : '每${config.interval}周$suffix';
    case RecurrenceFrequency.monthly:
      final mode = config.monthlyMode == 'weekday' ? '按星期' : '按日期';
      if (config.interval == 1) {
        return '每月$mode';
      }
      return '每${config.interval}个月$mode';
    case RecurrenceFrequency.yearly:
      if (config.interval == 1) {
        return '每年';
      }
      return '每${config.interval}年';
  }
}

String _weekdayLabel(int weekday) {
  const labels = {
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日',
  };
  return labels[weekday] ?? '周一';
}
