import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  List<Map<String, dynamic>> _recurringTasks = [];
  Set<String> _selectedDateCompletions = {};

  @override
  void initState() {
    super.initState();
    final now = AppTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    final startDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final endDate = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startStr = AppTime.formatDate(startDate);
    final endStr = AppTime.formatDate(endDate);

    final allTasks = await AppDatabase.getAllTasks();
    final sessions = await AppDatabase.getSessionsByDateRange(startStr, endStr);

    // Calculate stats per day
    final stats = <String, Map<String, dynamic>>{};
    for (final session in sessions) {
      final date = AppTime.formatDate(
          AppTime.fromMillisecondsSinceEpoch(session['startedAt'] as int));
      final existing = stats[date] ??
          {
            'focusMinutes': 0,
            'taskCount': 0,
            'completedCount': 0,
            'recurringCount': 0
          };
      existing['focusMinutes'] = (existing['focusMinutes'] as int) +
          ((session['durationSeconds'] as int) / 60).floor();
      stats[date] = existing;
    }

    // Recurring tasks
    final recurring = allTasks
        .where((t) => t['recurrenceConfig'] != null && t['dueDate'] != null)
        .toList();
    for (final task in recurring) {
      final dates = getRecurrenceDatesInRange(
        RecurrenceConfig.fromJson(
            task['recurrenceConfig'] as Map<String, dynamic>),
        task['dueDate'] as String,
        startStr,
        endStr,
      );
      for (final date in dates) {
        final dateStr = AppTime.formatDate(date);
        final existing = stats[dateStr] ??
            {
              'focusMinutes': 0,
              'taskCount': 0,
              'completedCount': 0,
              'recurringCount': 0
            };
        existing['recurringCount'] = (existing['recurringCount'] as int) + 1;
        stats[dateStr] = existing;
      }
    }

    setState(() {
      _dayStats = stats;
      _recurringTasks = recurring;
    });

    _loadDateDetail();
  }

  Future<void> _loadDateDetail() async {
    final allTasks = await AppDatabase.getAllTasks();
    final sessions = await AppDatabase.getSessionsByDate(_selectedDate);

    final dayTasks =
        allTasks.where((t) => t['dueDate'] == _selectedDate).toList();

    // Get recurring tasks for selected date
    final recurringOnDate = <Map<String, dynamic>>[];
    final completions = <String>{};
    for (final task in _recurringTasks) {
      final dates = getRecurrenceDatesInRange(
        RecurrenceConfig.fromJson(
            task['recurrenceConfig'] as Map<String, dynamic>),
        task['dueDate'] as String,
        _selectedDate,
        _selectedDate,
      );
      if (dates.isNotEmpty) {
        recurringOnDate.add(task);
        // Check if completed today
        final taskCompletions =
            await AppDatabase.getRecurrenceCompletionsByDateRange(
          task['id'] as String,
          _selectedDate,
          _selectedDate,
        );
        if (taskCompletions.isNotEmpty) {
          completions.add(task['id'] as String);
        }
      }
    }

    setState(() {
      _selectedDateSessions = sessions;
      _selectedDateTasks = dayTasks;
      _recurringTasks = recurringOnDate;
      _selectedDateCompletions = completions;
    });
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

    return SingleChildScrollView(
      child: Column(
        children: [
          // Calendar header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(year, month - 1, 1);
                    });
                    _loadMonthData();
                  },
                ),
                Text(
                  '$year年$month月',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(year, month + 1, 1);
                    });
                    _loadMonthData();
                  },
                ),
              ],
            ),
          ),

          // Weekday headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.3,
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
                        ? (isDark
                            ? AppColors.darkAccent
                            : AppColors.lightAccent)
                        : isToday
                            ? (isDark
                                ? AppColors.darkSurface
                                : AppColors.lightSurface)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday && !isSelected
                        ? Border.all(
                            color: isDark
                                ? AppColors.darkAccent
                                : AppColors.lightAccent,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day.toString(),
                        style: TextStyle(
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText),
                        ),
                      ),
                      if (stat != null) ...[
                        const SizedBox(height: 2),
                        // 使用 FittedBox 防止统计数字在小屏幕上溢出
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if ((stat['focusMinutes'] as int) > 0)
                                  Text(
                                    '${stat['focusMinutes']}m',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: isSelected
                                          ? Colors.white70
                                          : (isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary),
                                    ),
                                  ),
                                if ((stat['recurringCount'] as int) > 0)
                                  const Text(
                                    '🔄',
                                    style: TextStyle(fontSize: 8),
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
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 12),
                if (_selectedDateSessions.isNotEmpty ||
                    _selectedDateTasks.isNotEmpty ||
                    _recurringTasks.isNotEmpty) ...[
                  // 将统计信息改为 Wrap，防止在小屏幕上由于文字过长导致像素溢出
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (_selectedDateSessions.isNotEmpty)
                        Text(
                          '专注 ${_selectedDateSessions.fold<int>(0, (sum, s) => sum + ((s['durationSeconds'] as int) / 60).floor())} 分钟',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.lightText,
                          ),
                        ),
                      if (_selectedDateTasks.isNotEmpty)
                        Text(
                          '完成 ${_selectedDateTasks.where((t) => t['completed'] == true).length} 项任务',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (_recurringTasks.isNotEmpty) ...[
                  _buildSectionTitle('🔄 重复任务', isDark),
                  ..._recurringTasks.map((task) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              _selectedDateCompletions.contains(task['id'])
                                  ? '☑'
                                  : '☐',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              task['title'] as String,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                                decoration: _selectedDateCompletions
                                        .contains(task['id'])
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
                if (_selectedDateTasks.isNotEmpty) ...[
                  _buildSectionTitle('📅 普通任务', isDark),
                  ..._selectedDateTasks.map((task) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              task['completed'] == true ? '☑' : '☐',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              task['title'] as String,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.lightText,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
                if (_selectedDateSessions.isEmpty &&
                    _recurringTasks.isEmpty &&
                    _selectedDateTasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '暂无记录',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
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
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
      ),
    );
  }
}
