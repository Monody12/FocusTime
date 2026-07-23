import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/providers/time_zone_provider.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _currentMonth;
  String _selectedDate = AppTime.formatDate(AppTime.now());
  Map<String, Map<String, dynamic>> _dayStats = {};
  List<Map<String, dynamic>> _selectedDateSessions = [];
  List<Map<String, dynamic>> _selectedDateTasks = [];
  List<Map<String, dynamic>> _selectedDateRecurringTasks = [];
  Set<String> _selectedDateCompletions = {};
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

      final allTasks = await AppDatabase.getAllTasks();
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

      final recurring = allTasks
          .where((t) => t['recurrenceConfig'] != null && t['dueDate'] != null)
          .toList();
      for (final task in recurring) {
        final dates = getRecurrenceDatesInRange(
          RecurrenceConfig.fromJson(
            task['recurrenceConfig'] as Map<String, dynamic>,
          ),
          task['dueDate'] as String,
          startStr,
          endStr,
        );
        for (final date in dates) {
          final dateStr = AppTime.formatDate(date);
          final existing =
              stats[dateStr] ??
              {
                'focusMinutes': 0,
                'taskCount': 0,
                'completedCount': 0,
                'recurringCount': 0,
              };
          existing['recurringCount'] = (existing['recurringCount'] as int) + 1;
          stats[dateStr] = existing;
        }
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
      final allTasks = await AppDatabase.getAllTasks();
      final sessions = await AppDatabase.getSessionsByDate(selectedDate);
      final dayTasks = allTasks
          .where((t) => t['dueDate'] == selectedDate)
          .toList();
      final recurringCandidates = allTasks
          .where((t) => t['recurrenceConfig'] != null && t['dueDate'] != null)
          .toList();

      final recurringOnDate = <Map<String, dynamic>>[];
      final completions = <String>{};
      for (final task in recurringCandidates) {
        final dates = getRecurrenceDatesInRange(
          RecurrenceConfig.fromJson(
            task['recurrenceConfig'] as Map<String, dynamic>,
          ),
          task['dueDate'] as String,
          selectedDate,
          selectedDate,
        );
        if (dates.isNotEmpty) {
          recurringOnDate.add(task);
          final taskCompletions =
              await AppDatabase.getRecurrenceCompletionsByDateRange(
                task['id'] as String,
                selectedDate,
                selectedDate,
              );
          if (taskCompletions.isNotEmpty) {
            completions.add(task['id'] as String);
          }
        }
      }

      if (!mounted ||
          request != _detailLoadRequest ||
          selectedDate != _selectedDate) {
        return;
      }
      setState(() {
        _selectedDateSessions = sessions;
        _selectedDateTasks = dayTasks;
        _selectedDateRecurringTasks = recurringOnDate;
        _selectedDateCompletions = completions;
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
                      .clamp(44.0, 80.0)
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
                                        if ((stat['recurringCount'] as int) > 0)
                                          AppIcon(
                                            AppIcons.repeat,
                                            size: 8,
                                            color: isSelected
                                                ? Colors.white70
                                                : context
                                                      .appColors
                                                      .textSecondary,
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
                        _selectedDateTasks.isNotEmpty ||
                        _selectedDateRecurringTasks.isNotEmpty) ...[
                      // 将统计信息改为 Wrap，防止在小屏幕上由于文字过长导致像素溢出
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (_selectedDateSessions.isNotEmpty)
                            Text(
                              '专注 ${_selectedDateSessions.fold<int>(0, (sum, s) => sum + ((s['durationSeconds'] as int) / 60).floor())} 分钟',
                              style: TextStyle(color: context.appColors.text),
                            ),
                          if (_selectedDateTasks.isNotEmpty)
                            Text(
                              '完成 ${_selectedDateTasks.where((t) => t['completed'] == true).length} 项任务',
                              style: TextStyle(
                                color: context.appColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_selectedDateRecurringTasks.isNotEmpty) ...[
                      _buildSectionTitle('🔄 重复任务', isDark),
                      ..._selectedDateRecurringTasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                _selectedDateCompletions.contains(task['id'])
                                    ? '☑'
                                    : '☐',
                                style: TextStyle(color: context.appColors.text),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task['title'] as String,
                                  style: TextStyle(
                                    color: context.appColors.text,
                                    decoration:
                                        _selectedDateCompletions.contains(
                                          task['id'],
                                        )
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_selectedDateTasks.isNotEmpty) ...[
                      _buildSectionTitle('📅 普通任务', isDark),
                      ..._selectedDateTasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                task['completed'] == true ? '☑' : '☐',
                                style: TextStyle(color: context.appColors.text),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task['title'] as String,
                                  style: TextStyle(
                                    color: context.appColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_selectedDateSessions.isEmpty &&
                        _selectedDateRecurringTasks.isEmpty &&
                        _selectedDateTasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            '暂无记录',
                            style: TextStyle(
                              color: context.appColors.textSecondary,
                            ),
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
}
