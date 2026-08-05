import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/providers/time_zone_provider.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/calendar/models/calendar_task_activity.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

typedef CalendarTaskSelected = void Function(String taskId);

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, required this.onTaskSelected});

  final CalendarTaskSelected onTaskSelected;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _currentMonth;
  String _selectedDate = AppTime.formatDate(AppTime.now());
  Map<String, Map<String, dynamic>> _dayStats = {};
  List<Map<String, dynamic>> _selectedDateSessions = [];
  List<CalendarTaskActivity> _selectedDateActivities = [];
  int _monthLoadRequest = 0;
  int _detailLoadRequest = 0;

  @override
  void initState() {
    super.initState();
    final now = AppTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    final request = ++_monthLoadRequest;
    final month = _currentMonth;
    try {
      final startDate = DateTime(month.year, month.month, 1);
      final endDate = DateTime(month.year, month.month + 1, 0);
      final startStr = AppTime.formatDate(startDate);
      final endStr = AppTime.formatDate(endDate);

      final allTasks = await AppDatabase.getCalendarTasksByDateRange(
        startStr,
        endStr,
      );
      final sessions = await AppDatabase.getSessionsByDateRange(
        startStr,
        endStr,
      );

      final stats = <String, Map<String, dynamic>>{};
      for (final session in sessions) {
        final date = AppTime.formatDate(
          AppTime.fromMillisecondsSinceEpoch(session['startedAt'] as int),
        );
        final existing =
            stats[date] ??
            {
              'focusMinutes': 0,
              'taskCount': 0,
              'completedCount': 0,
              'recurringCount': 0,
            };
        existing['focusMinutes'] =
            (existing['focusMinutes'] as int) +
            ((session['durationSeconds'] as int) / 60).floor();
        stats[date] = existing;
      }

      final taskStats = buildCalendarTaskStats(
        tasks: allTasks,
        startDate: startStr,
        endDate: endStr,
      );
      for (final entry in taskStats.entries) {
        final existing =
            stats[entry.key] ??
            {
              'focusMinutes': 0,
              'taskCount': 0,
              'completedCount': 0,
              'recurringCount': 0,
            };
        existing['taskCount'] = entry.value.taskCount;
        existing['completedCount'] = entry.value.completedCount;
        existing['recurringCount'] = entry.value.recurringCount;
        stats[entry.key] = existing;
      }

      if (!mounted || request != _monthLoadRequest || month != _currentMonth) {
        return;
      }
      setState(() => _dayStats = stats);
      await _loadDateDetail();
    } catch (_) {
      if (!mounted || request != _monthLoadRequest) return;
      _showLoadError();
    }
  }

  Future<void> _loadDateDetail() async {
    final request = ++_detailLoadRequest;
    final selectedDate = _selectedDate;
    try {
      final allTasks = await AppDatabase.getCalendarTasksByDateRange(
        selectedDate,
        selectedDate,
      );
      final sessions = await AppDatabase.getSessionsByDate(selectedDate);
      final recurrenceCompletions =
          await AppDatabase.getAllRecurrenceCompletionsByDateRange(
            selectedDate,
            selectedDate,
          );
      final activities = buildCalendarTaskActivities(
        tasks: allTasks,
        date: selectedDate,
        recurrenceCompletedTaskIds: recurrenceCompletions
            .map((item) => item['taskId'] as String)
            .toSet(),
      );

      if (!mounted ||
          request != _detailLoadRequest ||
          selectedDate != _selectedDate) {
        return;
      }
      setState(() {
        _selectedDateSessions = sessions;
        _selectedDateActivities = activities;
      });
    } catch (_) {
      if (!mounted || request != _detailLoadRequest) return;
      _showLoadError();
    }
  }

  void _showLoadError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日历数据加载失败，请稍后重试')));
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + offset,
      1,
    );
    final selectedDay = DateTime.tryParse(_selectedDate)?.day ?? 1;
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    final nextSelectedDate = DateTime(
      nextMonth.year,
      nextMonth.month,
      selectedDay.clamp(1, lastDay),
    );
    setState(() {
      _currentMonth = nextMonth;
      _selectedDate = AppTime.formatDate(nextSelectedDate);
    });
    _loadMonthData();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for session updates to refresh calendar data
    ref.listen(sessionUpdateProvider, (previous, next) {
      if (previous != next) {
        _loadMonthData();
      }
    });
    ref.listen(taskProvider.select((state) => state.tasks), (previous, next) {
      if (!identical(previous, next)) {
        _loadMonthData();
      }
    });
    ref.listen(timeZoneProvider, (previous, next) {
      if (previous != next) {
        final now = AppTime.now();
        setState(() {
          _selectedDate = AppTime.formatDate(now);
          _currentMonth = DateTime(now.year, now.month, 1);
        });
        _loadMonthData();
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = AppTime.formatDate(AppTime.now());
    final year = _currentMonth.year;
    final month = _currentMonth.month;

    final firstDayOfWeek = DateTime(year, month, 1).weekday;
    final offset = firstDayOfWeek == 7 ? 0 : firstDayOfWeek;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final rowCount = ((offset + daysInMonth + 6) ~/ 7);

    return LayoutBuilder(
      builder: (context, pageConstraints) {
        // Leave room for the selected date and its empty state on first view.
        final heightCellLimit = pageConstraints.hasBoundedHeight
            ? (pageConstraints.maxHeight - 216) / rowCount
            : 80.0;

        return SingleChildScrollView(
          child: Column(
            children: [
              // Calendar header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(AppIcons.previous),
                      tooltip: '上个月',
                      onPressed: () => _changeMonth(-1),
                    ),
                    Text(
                      '$year年$month月',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.appColors.text,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(AppIcons.next),
                      tooltip: '下个月',
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
              ),

              // Weekday headers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['一', '二', '三', '四', '五', '六', '日']
                      .map(
                        (d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

              const SizedBox(height: 8),

              // Calendar grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = (constraints.maxWidth - 32) / 7;
                  final cellHeight = math
                      .min(cellWidth / 1.3, heightCellLimit)
                      .clamp(42.0, 64.0)
                      .toDouble();
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: cellHeight,
                    ),
                    itemCount: offset + daysInMonth,
                    itemBuilder: (context, index) {
                      if (index < offset) {
                        return const SizedBox();
                      }
                      final day = index - offset + 1;
                      final dateStr =
                          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                      final stat = _dayStats[dateStr];
                      final isToday = dateStr == today;
                      final isSelected = dateStr == _selectedDate;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDate = dateStr);
                          _loadDateDetail();
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (context.appColors.accent)
                                : isToday
                                ? (context.appColors.surface)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(color: context.appColors.accent)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                day.toString(),
                                style: TextStyle(
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : (context.appColors.text),
                                ),
                              ),
                              if (stat != null) ...[
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if ((stat['focusMinutes'] as int) > 0)
                                          Text(
                                            '${stat['focusMinutes']}m',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: isSelected
                                                  ? Colors.white70
                                                  : context
                                                        .appColors
                                                        .textSecondary,
                                            ),
                                          ),
                                        if ((stat['focusMinutes'] as int) > 0 &&
                                            (stat['taskCount'] as int) > 0)
                                          const SizedBox(width: 3),
                                        if ((stat['taskCount'] as int) > 0) ...[
                                          Text(
                                            '${stat['taskCount']}项',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isSelected
                                                  ? Colors.white70
                                                  : context
                                                        .appColors
                                                        .textSecondary,
                                            ),
                                          ),
                                        ],
                                        if ((stat['recurringCount'] as int) > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 3,
                                            ),
                                            child: AppIcon(
                                              AppIcons.repeat,
                                              size: 10,
                                              color: isSelected
                                                  ? Colors.white70
                                                  : context
                                                        .appColors
                                                        .textSecondary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const Divider(height: 16),

              // Selected date detail
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedDate == today ? '今天' : _selectedDate,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.appColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedDateSessions.isNotEmpty ||
                        _selectedDateActivities.isNotEmpty) ...[
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (_selectedDateActivities.isNotEmpty)
                            _buildMetric(
                              AppIcons.tasks,
                              '${_selectedDateActivities.length} 个相关任务',
                            ),
                          if (_selectedDateActivities.any(
                            (activity) => activity.isCompleted,
                          ))
                            _buildMetric(
                              AppIcons.taskComplete,
                              '${_selectedDateActivities.where((activity) => activity.isCompleted).length} 个当前已完成',
                            ),
                          if (_selectedDateSessions.isNotEmpty)
                            _buildMetric(
                              AppIcons.focus,
                              '专注 ${_selectedDateSessions.fold<int>(0, (sum, s) => sum + ((s['durationSeconds'] as int) / 60).floor())} 分钟',
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_selectedDateActivities.isNotEmpty) ...[
                      _buildSectionTitle('当天任务', isDark),
                      ..._selectedDateActivities.map(_buildActivityRow),
                    ],
                    if (_selectedDateSessions.isEmpty &&
                        _selectedDateActivities.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              AppIcon(
                                AppIcons.emptyTasks,
                                size: AppIconSizes.empty,
                                color: context.appColors.border,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '当天没有任务记录',
                                style: TextStyle(
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.appColors.text,
        ),
      ),
    );
  }

  Widget _buildMetric(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          icon,
          size: AppIconSizes.status,
          color: context.appColors.textSecondary,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.appColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRow(CalendarTaskActivity activity) {
    final completed = activity.isCompleted;
    final (
      activityIcon,
      activityLabel,
      activityColor,
    ) = switch (activity.primaryKind) {
      CalendarTaskActivityKind.createdAndCompleted => (
        AppIcons.taskComplete,
        '当天创建并完成',
        context.appColors.success,
      ),
      CalendarTaskActivityKind.completed => (
        AppIcons.taskComplete,
        '当天完成',
        context.appColors.success,
      ),
      CalendarTaskActivityKind.created => (
        AppIcons.add,
        '当天创建',
        context.appColors.accentSecondary,
      ),
      CalendarTaskActivityKind.recurring => (
        AppIcons.repeat,
        '循环计划',
        context.appColors.accent,
      ),
      CalendarTaskActivityKind.due => (
        AppIcons.calendar,
        '截止当天',
        context.appColors.warning,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => widget.onTaskSelected(activity.id),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: context.appColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildCompletionMark(completed),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: completed
                              ? context.appColors.textSecondary
                              : context.appColors.text,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 10,
                        runSpacing: 5,
                        children: [
                          _buildActivityMeta(
                            activityIcon,
                            activityLabel,
                            activityColor,
                          ),
                          if (activity.recurringOnDate &&
                              activity.primaryKind !=
                                  CalendarTaskActivityKind.recurring)
                            _buildActivityMeta(
                              AppIcons.repeat,
                              '循环',
                              context.appColors.accent,
                            ),
                          if (activity.dueOnDate &&
                              activity.primaryKind !=
                                  CalendarTaskActivityKind.due)
                            _buildActivityMeta(
                              AppIcons.calendar,
                              '截止',
                              context.appColors.textSecondary,
                            ),
                          if (activity.archived)
                            _buildActivityMeta(
                              AppIcons.archive,
                              '已归档',
                              context.appColors.warning,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(
                  AppIcons.arrowForward,
                  size: AppIconSizes.compact,
                  color: context.appColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionMark(bool completed) {
    return Semantics(
      label: completed ? '已完成' : '未完成',
      checked: completed,
      child: ExcludeSemantics(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: completed ? context.appColors.success : Colors.transparent,
            border: Border.all(
              color: completed
                  ? context.appColors.success
                  : context.appColors.border,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: completed
              ? const Icon(AppIcons.taskDone, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _buildActivityMeta(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
