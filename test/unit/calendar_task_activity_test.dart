import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/calendar/models/calendar_task_activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    AppTime.configure(AppTimeZoneMode.beijing);
  });

  tearDown(() {
    AppTime.configure(AppTimeZoneMode.system);
  });

  Map<String, dynamic> task({
    required String id,
    required String title,
    required int createdAt,
    bool completed = false,
    int? completedAt,
    String? dueDate,
    Map<String, dynamic>? recurrenceConfig,
    bool archived = false,
    int? archivedAt,
  }) {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt,
      'completed': completed,
      'completedAt': completedAt,
      'dueDate': dueDate,
      'dueTime': null,
      'recurrenceConfig': recurrenceConfig,
      'archived': archived,
      'archivedAt': archivedAt,
    };
  }

  group('calendar task activity aggregation', () {
    test('a task created and completed on the same day appears once', () {
      final createdAt = AppTime.create(2026, 8, 5, 9).millisecondsSinceEpoch;
      final completedAt = AppTime.create(2026, 8, 5, 11).millisecondsSinceEpoch;

      final activities = buildCalendarTaskActivities(
        tasks: [
          task(
            id: 'same-day',
            title: '当天闭环',
            createdAt: createdAt,
            completed: true,
            completedAt: completedAt,
            dueDate: '2026-08-05',
          ),
        ],
        date: '2026-08-05',
      );

      expect(activities, hasLength(1));
      expect(
        activities.single.primaryKind,
        CalendarTaskActivityKind.createdAndCompleted,
      );
      expect(activities.single.isCompleted, true);
      expect(activities.single.dueOnDate, true);
    });

    test('creation-day checkbox reflects the current completion state', () {
      final activity = buildCalendarTaskActivities(
        tasks: [
          task(
            id: 'completed-later',
            title: '后来完成',
            createdAt: AppTime.create(2026, 8, 5, 23).millisecondsSinceEpoch,
            completed: true,
            completedAt: AppTime.create(2026, 8, 6, 1).millisecondsSinceEpoch,
          ),
        ],
        date: '2026-08-05',
      ).single;

      expect(activity.primaryKind, CalendarTaskActivityKind.created);
      expect(activity.completedOnDate, false);
      expect(activity.isCompleted, true);
    });

    test('archived tasks remain in the activity list', () {
      final activities = buildCalendarTaskActivities(
        tasks: [
          task(
            id: 'archived',
            title: '已归档任务',
            createdAt: AppTime.create(2026, 8, 5).millisecondsSinceEpoch,
            archived: true,
          ),
        ],
        date: '2026-08-05',
      );

      expect(activities.single.archived, true);
    });

    test('archived tasks do not create future schedule occurrences', () {
      final archivedRecurringTask = task(
        id: 'archived-recurring',
        title: '停止的循环任务',
        createdAt: AppTime.create(2026, 8, 1).millisecondsSinceEpoch,
        dueDate: '2026-08-01',
        recurrenceConfig: {'frequency': 'daily', 'interval': 1},
        archived: true,
        archivedAt: AppTime.create(2026, 8, 5, 18).millisecondsSinceEpoch,
      );

      expect(
        buildCalendarTaskActivities(
          tasks: [archivedRecurringTask],
          date: '2026-08-05',
        ).single.recurringOnDate,
        true,
      );
      expect(
        buildCalendarTaskActivities(
          tasks: [archivedRecurringTask],
          date: '2026-08-06',
        ),
        isEmpty,
      );
      expect(
        buildCalendarTaskStats(
          tasks: [archivedRecurringTask],
          startDate: '2026-08-01',
          endDate: '2026-08-31',
        ).containsKey('2026-08-06'),
        false,
      );
    });

    test(
      'month stats deduplicate created, completed, due and recurring data',
      () {
        final stats = buildCalendarTaskStats(
          tasks: [
            task(
              id: 'all-markers',
              title: '多来源任务',
              createdAt: AppTime.create(2026, 8, 5, 8).millisecondsSinceEpoch,
              completed: true,
              completedAt: AppTime.create(2026, 8, 5, 9).millisecondsSinceEpoch,
              dueDate: '2026-08-05',
              recurrenceConfig: {'frequency': 'daily', 'interval': 1},
            ),
          ],
          startDate: '2026-08-01',
          endDate: '2026-08-31',
        );

        expect(stats['2026-08-05']!.taskCount, 1);
        expect(stats['2026-08-05']!.completedCount, 1);
        expect(stats['2026-08-05']!.recurringCount, 1);
        expect(stats['2026-08-06']!.taskCount, 1);
      },
    );

    test('malformed recurrence does not hide a valid creation record', () {
      final activities = buildCalendarTaskActivities(
        tasks: [
          task(
            id: 'malformed',
            title: '损坏循环配置',
            createdAt: AppTime.create(2026, 8, 5).millisecondsSinceEpoch,
            dueDate: 'not-a-date',
            recurrenceConfig: {'frequency': 'daily', 'interval': 0},
          ),
        ],
        date: '2026-08-05',
      );

      expect(activities, hasLength(1));
      expect(activities.single.primaryKind, CalendarTaskActivityKind.created);
      expect(activities.single.recurringOnDate, false);
    });
  });

  test(
    'calendar range query includes archived tasks and excludes soft deletes',
    () async {
      final createdAt = AppTime.create(2026, 8, 5, 10).millisecondsSinceEpoch;
      final created = await AppDatabase.createTask(
        listId: 'system-all-tasks',
        title: '归档日历查询',
      );
      final taskId = created['id'] as String;
      final db = await AppDatabase.database;
      await db.update(
        'tasks',
        {'created_at': createdAt},
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await AppDatabase.archiveTask(taskId);

      final archived = await AppDatabase.getCalendarTasksByDateRange(
        '2026-08-05',
        '2026-08-05',
      );
      final archivedTask = archived.singleWhere((item) => item['id'] == taskId);
      expect(archivedTask['archived'], true);
      expect(archivedTask['listName'], '任务');
      expect(
        await AppDatabase.getTaskById(taskId, includeArchived: true),
        isNotNull,
      );

      await AppDatabase.deleteTask(taskId);
      final afterDelete = await AppDatabase.getCalendarTasksByDateRange(
        '2026-08-05',
        '2026-08-05',
      );
      expect(afterDelete.where((item) => item['id'] == taskId), isEmpty);
    },
  );
}
