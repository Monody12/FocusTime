import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('任务同步负载包含所有任务字段并可应用备注变更', () async {
    final reminderAt = DateTime(2026, 6, 10, 9).millisecondsSinceEpoch;
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '同步字段测试',
      notes: 'Windows 添加的备注',
      dueDate: '2026-06-10',
      dueTime: '10:30',
      isMyDay: true,
      expectedMinutes: 90,
      reminderAt: reminderAt,
    );

    final taskId = task['id'] as String;
    await AppDatabase.updateTask(taskId, {
      'isImportant': true,
      'calendarEventId': 'calendar-event-1',
    });

    final payload = await AppDatabase.getSyncPayload(0);
    final syncedTask = payload['tasks']!.firstWhere(
      (record) => record['id'] == taskId,
    );
    final data = syncedTask['data'] as Map<String, dynamic>;

    expect(data['id'], taskId);
    expect(data['listId'], 'system-all-tasks');
    expect(data['title'], '同步字段测试');
    expect(data['notes'], 'Windows 添加的备注');
    expect(data['completed'], false);
    expect(data['completedAt'], isNull);
    expect(data['dueDate'], '2026-06-10');
    expect(data['dueTime'], '10:30');
    expect(data['sortOrder'], isA<int>());
    expect(data['isMyDay'], true);
    expect(data['myDayAddedAt'], isA<int>());
    expect(data['recurrenceConfig'], isNull);
    expect(data['expectedMinutes'], 90);
    expect(data['isImportant'], true);
    expect(data['reminderAt'], reminderAt);
    expect(data.containsKey('calendarEventId'), false);
    expect(data['createdAt'], isA<int>());
    expect(data['updatedAt'], isA<int>());
    expect(data['archived'], false);
    expect(data['archivedAt'], isNull);
    expect(data['deleted'], false);

    await AppDatabase.applySyncChanges({
      'tasks': [
        {
          'id': taskId,
          'updatedAt': (data['updatedAt'] as int) + 1,
          'deleted': false,
          'data': {
            ...data,
            'notes': 'Android 应看到的备注',
            'calendarEventId': 'remote-calendar-event',
          },
        }
      ],
    });

    final updatedTask = await AppDatabase.getTaskById(taskId);
    expect(updatedTask!['notes'], 'Android 应看到的备注');
    expect(updatedTask['calendarEventId'], 'calendar-event-1');

    await AppDatabase.archiveTask(taskId);
    expect(await AppDatabase.getTaskById(taskId), isNull);

    final archivedTasks = await AppDatabase.getArchivedTasks();
    final archivedTask =
        archivedTasks.firstWhere((record) => record['id'] == taskId);
    expect(archivedTask['archived'], true);
    expect(archivedTask['archivedAt'], isA<int>());

    final archivePayload = await AppDatabase.getSyncPayload(0);
    final syncedArchivedTask = archivePayload['tasks']!.firstWhere(
      (record) => record['id'] == taskId,
    );
    final archivedData = syncedArchivedTask['data'] as Map<String, dynamic>;
    expect(archivedData['archived'], true);
    expect(archivedData['archivedAt'], isA<int>());

    await AppDatabase.deleteTask(taskId);
  });

  test('本机日历事件 ID 更新不会触发任务同步', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '本机日历字段测试',
    );
    final taskId = task['id'] as String;
    final originalUpdatedAt = task['updatedAt'] as int;

    await AppDatabase.updateTaskCalendarEventId(taskId, 'android-event-local');

    final updatedTask = await AppDatabase.getTaskById(taskId);
    expect(updatedTask!['calendarEventId'], 'android-event-local');
    expect(updatedTask['updatedAt'], originalUpdatedAt);

    final payload = await AppDatabase.getSyncPayload(originalUpdatedAt);
    expect(
      payload['tasks']!.where((record) => record['id'] == taskId),
      isEmpty,
    );

    await AppDatabase.deleteTask(taskId);
  });
}
