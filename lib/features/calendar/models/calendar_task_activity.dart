import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';

enum CalendarTaskActivityKind {
  createdAndCompleted,
  completed,
  created,
  recurring,
  due,
}

class CalendarTaskActivity {
  const CalendarTaskActivity({
    required this.task,
    required this.date,
    required this.createdOnDate,
    required this.completedOnDate,
    required this.dueOnDate,
    required this.recurringOnDate,
    required this.recurrenceCompleted,
  });

  final Map<String, dynamic> task;
  final String date;
  final bool createdOnDate;
  final bool completedOnDate;
  final bool dueOnDate;
  final bool recurringOnDate;
  final bool recurrenceCompleted;

  String get id => task['id'] as String;
  String get title => task['title'] as String;
  bool get archived => task['archived'] == true;
  bool get isCompleted => task['completed'] == true || recurrenceCompleted;

  CalendarTaskActivityKind get primaryKind {
    if (createdOnDate && completedOnDate) {
      return CalendarTaskActivityKind.createdAndCompleted;
    }
    if (completedOnDate) return CalendarTaskActivityKind.completed;
    if (createdOnDate) return CalendarTaskActivityKind.created;
    if (recurringOnDate) return CalendarTaskActivityKind.recurring;
    return CalendarTaskActivityKind.due;
  }

  int get sortTimestamp {
    if (completedOnDate) return task['completedAt'] as int? ?? 0;
    if (createdOnDate) return task['createdAt'] as int? ?? 0;
    final dueTime = task['dueTime'] as String?;
    if (dueTime == null) return 0;
    final parts = dueTime.split(':');
    if (parts.length != 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }
}

class CalendarDayTaskStats {
  const CalendarDayTaskStats({
    required this.taskCount,
    required this.completedCount,
    required this.recurringCount,
  });

  final int taskCount;
  final int completedCount;
  final int recurringCount;
}

List<CalendarTaskActivity> buildCalendarTaskActivities({
  required List<Map<String, dynamic>> tasks,
  required String date,
  Set<String> recurrenceCompletedTaskIds = const {},
}) {
  final activities = <CalendarTaskActivity>[];

  for (final task in tasks) {
    final createdOnDate = _timestampDate(task['createdAt'] as int?) == date;
    final completedOnDate = _timestampDate(task['completedAt'] as int?) == date;
    final scheduledOnDate = _scheduleIncludesDate(task, date);
    final dueOnDate = scheduledOnDate && task['dueDate'] == date;
    final recurringOnDate = scheduledOnDate && _recursOnDate(task, date);
    if (!createdOnDate && !completedOnDate && !dueOnDate && !recurringOnDate) {
      continue;
    }

    activities.add(
      CalendarTaskActivity(
        task: task,
        date: date,
        createdOnDate: createdOnDate,
        completedOnDate: completedOnDate,
        dueOnDate: dueOnDate,
        recurringOnDate: recurringOnDate,
        recurrenceCompleted: recurrenceCompletedTaskIds.contains(task['id']),
      ),
    );
  }

  activities.sort((a, b) {
    final timeComparison = b.sortTimestamp.compareTo(a.sortTimestamp);
    if (timeComparison != 0) return timeComparison;
    return a.title.compareTo(b.title);
  });
  return activities;
}

Map<String, CalendarDayTaskStats> buildCalendarTaskStats({
  required List<Map<String, dynamic>> tasks,
  required String startDate,
  required String endDate,
}) {
  final taskIds = <String, Set<String>>{};
  final completedTaskIds = <String, Set<String>>{};
  final recurringTaskIds = <String, Set<String>>{};

  for (final task in tasks) {
    final id = task['id'] as String;
    final createdDate = _timestampDate(task['createdAt'] as int?);
    final completedDate = _timestampDate(task['completedAt'] as int?);
    final dueDate = task['dueDate'] as String?;

    if (_dateInRange(createdDate, startDate, endDate)) {
      taskIds.putIfAbsent(createdDate!, () => <String>{}).add(id);
    }
    if (_dateInRange(completedDate, startDate, endDate)) {
      taskIds.putIfAbsent(completedDate!, () => <String>{}).add(id);
      completedTaskIds.putIfAbsent(completedDate, () => <String>{}).add(id);
    }
    if (_dateInRange(dueDate, startDate, endDate) &&
        _scheduleIncludesDate(task, dueDate!)) {
      taskIds.putIfAbsent(dueDate, () => <String>{}).add(id);
    }

    for (final recurrenceDate in _recurrenceDates(task, startDate, endDate)) {
      taskIds.putIfAbsent(recurrenceDate, () => <String>{}).add(id);
      recurringTaskIds.putIfAbsent(recurrenceDate, () => <String>{}).add(id);
    }
  }

  final allDates = <String>{
    ...taskIds.keys,
    ...completedTaskIds.keys,
    ...recurringTaskIds.keys,
  };
  return {
    for (final date in allDates)
      date: CalendarDayTaskStats(
        taskCount: taskIds[date]?.length ?? 0,
        completedCount: completedTaskIds[date]?.length ?? 0,
        recurringCount: recurringTaskIds[date]?.length ?? 0,
      ),
  };
}

String? _timestampDate(int? timestamp) {
  if (timestamp == null) return null;
  return AppTime.formatDate(AppTime.fromMillisecondsSinceEpoch(timestamp));
}

bool _dateInRange(String? date, String startDate, String endDate) {
  return date != null &&
      date.compareTo(startDate) >= 0 &&
      date.compareTo(endDate) <= 0;
}

bool _recursOnDate(Map<String, dynamic> task, String date) {
  return _recurrenceDates(task, date, date).isNotEmpty;
}

List<String> _recurrenceDates(
  Map<String, dynamic> task,
  String startDate,
  String endDate,
) {
  final rawConfig = task['recurrenceConfig'];
  final dueDate = task['dueDate'];
  if (rawConfig is! Map<String, dynamic> || dueDate is! String) {
    return const [];
  }

  final scheduleEndDate = _scheduleEndDate(task);
  final effectiveEndDate =
      scheduleEndDate != null && scheduleEndDate.compareTo(endDate) < 0
      ? scheduleEndDate
      : endDate;
  if (startDate.compareTo(effectiveEndDate) > 0) return const [];

  try {
    return getRecurrenceDatesInRange(
      RecurrenceConfig.fromJson(rawConfig),
      dueDate,
      startDate,
      effectiveEndDate,
    ).map(AppTime.formatDate).toList();
  } catch (_) {
    // A malformed synced recurrence must not hide the rest of the calendar.
    return const [];
  }
}

bool _scheduleIncludesDate(Map<String, dynamic> task, String date) {
  final scheduleEndDate = _scheduleEndDate(task);
  return scheduleEndDate == null || date.compareTo(scheduleEndDate) <= 0;
}

String? _scheduleEndDate(Map<String, dynamic> task) {
  if (task['archived'] != true) return null;
  return _timestampDate(task['archivedAt'] as int?);
}
