enum RecurrenceFrequency { daily, weekly, monthly, yearly }

class RecurrenceConfig {
  final RecurrenceFrequency frequency;
  final int interval;
  final List<int>? daysOfWeek;
  final int? dayOfMonth;
  final int? weekOrdinal;
  final int? weekDay;
  final int? monthOfYear;
  final String? endsAt;

  RecurrenceConfig({
    required this.frequency,
    this.interval = 1,
    this.daysOfWeek,
    this.dayOfMonth,
    this.weekOrdinal,
    this.weekDay,
    this.monthOfYear,
    this.endsAt,
  });

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
        if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
        if (weekOrdinal != null) 'weekOrdinal': weekOrdinal,
        if (weekDay != null) 'weekDay': weekDay,
        if (monthOfYear != null) 'monthOfYear': monthOfYear,
        if (endsAt != null) 'endsAt': endsAt,
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
      dayOfMonth: json['dayOfMonth'],
      weekOrdinal: json['weekOrdinal'],
      weekDay: json['weekDay'],
      monthOfYear: json['monthOfYear'],
      endsAt: json['endsAt'],
    );
  }

  RecurrenceConfig copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? weekOrdinal,
    int? weekDay,
    int? monthOfYear,
    String? endsAt,
  }) {
    return RecurrenceConfig(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      weekOrdinal: weekOrdinal ?? this.weekOrdinal,
      weekDay: weekDay ?? this.weekDay,
      monthOfYear: monthOfYear ?? this.monthOfYear,
      endsAt: endsAt ?? this.endsAt,
    );
  }
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
  final anchor = DateTime.parse(anchorDate);

  // 如果开始日期在锚点之前，从锚点开始
  if (current.isBefore(start)) {
    current = _getNextDate(current, config, anchor);
  }

  while (!current.isAfter(end)) {
    if (!current.isBefore(start)) {
      dates.add(current);
    }
    current = _getNextDate(current, config, anchor);
  }

  return dates;
}

DateTime _getNextDate(DateTime current, RecurrenceConfig config, DateTime anchor) {
  switch (config.frequency) {
    case RecurrenceFrequency.daily:
      return current.add(Duration(days: config.interval));
    case RecurrenceFrequency.weekly:
      if (config.daysOfWeek != null && config.daysOfWeek!.isNotEmpty) {
        // 找到下周同类型的日期
        var next = current.add(Duration(days: 1));
        int count = 0;
        while (count < 7 * config.interval) {
          if (config.daysOfWeek!.contains(next.weekday % 7)) {
            return next;
          }
          next = next.add(const Duration(days: 1));
          count++;
        }
        return next;
      }
      return current.add(Duration(days: 7 * config.interval));
    case RecurrenceFrequency.monthly:
      return DateTime(
        current.year,
        current.month + config.interval,
        current.day,
      );
    case RecurrenceFrequency.yearly:
      return DateTime(
        current.year + config.interval,
        current.month,
        current.day,
      );
  }
}

String getRecurrenceSummary(RecurrenceConfig config) {
  switch (config.frequency) {
    case RecurrenceFrequency.daily:
      if (config.interval == 1) {
        return '每天';
      }
      return '每${config.interval}天';
    case RecurrenceFrequency.weekly:
      if (config.interval == 1) {
        return '每周';
      }
      return '每${config.interval}周';
    case RecurrenceFrequency.monthly:
      if (config.interval == 1) {
        return '每月';
      }
      return '每${config.interval}个月';
    case RecurrenceFrequency.yearly:
      if (config.interval == 1) {
        return '每年';
      }
      return '每${config.interval}年';
  }
}