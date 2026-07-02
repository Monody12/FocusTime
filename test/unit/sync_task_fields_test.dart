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
    expect(data['_fieldUpdatedAt'], isA<Map>());
    final fieldUpdatedAt = Map<String, dynamic>.from(
      data['_fieldUpdatedAt'] as Map,
    );
    expect(fieldUpdatedAt['title'], isA<int>());
    expect(fieldUpdatedAt['notes'], isA<int>());
    expect(fieldUpdatedAt['reminderAt'], isA<int>());

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

  test('任务字段级合并会保留本机较新的字段并套用远端较新的字段', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '原始标题',
      notes: '原始备注',
    );
    final taskId = task['id'] as String;

    final basePayload = await AppDatabase.getSyncPayload(0);
    final baseRecord = basePayload['tasks']!.firstWhere(
      (record) => record['id'] == taskId,
    );
    final baseData =
        Map<String, dynamic>.from(baseRecord['data'] as Map<String, dynamic>);
    final baseFieldUpdatedAt = Map<String, dynamic>.from(
      baseData['_fieldUpdatedAt'] as Map,
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.updateTask(taskId, {'title': '本机新标题'});
    await AppDatabase.updateTaskCalendarEventId(taskId, 'local-calendar-id');
    final localTask = await AppDatabase.getTaskById(taskId);
    final localTitleUpdatedAt = localTask!['updatedAt'] as int;
    final remoteNotesUpdatedAt = localTitleUpdatedAt + 10;

    await AppDatabase.applySyncChanges({
      'tasks': [
        {
          'id': taskId,
          'updatedAt': remoteNotesUpdatedAt,
          'deleted': false,
          'data': {
            ...baseData,
            'title': '远端旧标题',
            'notes': '远端新备注',
            'updatedAt': remoteNotesUpdatedAt,
            '_fieldUpdatedAt': {
              ...baseFieldUpdatedAt,
              'title': baseFieldUpdatedAt['title'],
              'notes': remoteNotesUpdatedAt,
            },
          },
        }
      ],
    });

    final mergedTask = await AppDatabase.getTaskById(taskId);
    expect(mergedTask!['title'], '本机新标题');
    expect(mergedTask['notes'], '远端新备注');
    expect(mergedTask['calendarEventId'], 'local-calendar-id');

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

  test('本机同步凭据和服务端游标不会进入 settings 同步负载', () async {
    await AppDatabase.setSetting('syncToken', 'local-token');
    await AppDatabase.setSetting('syncUserId', 'local-user');
    await AppDatabase.setSetting('syncUsername', 'alice');
    await AppDatabase.setSetting('syncFakePassword', '••••••••');
    await AppDatabase.setSetting('syncRealPassword', 'encrypted-password');
    await AppDatabase.setSetting('lastSyncTime', '123');
    await AppDatabase.setSetting('lastServerSyncCursor', '456');
    await AppDatabase.setSetting('deepseekApiKey', 'local-ai-key');
    await AppDatabase.setSetting('themeScheme', 'twilight');

    final payload = await AppDatabase.getSyncPayload(0);
    final settingKeys = payload['settings']!
        .map((record) => (record['data'] as Map<String, dynamic>)['key'])
        .toSet();

    expect(settingKeys, contains('themeScheme'));
    expect(settingKeys, isNot(contains('syncToken')));
    expect(settingKeys, isNot(contains('syncUserId')));
    expect(settingKeys, isNot(contains('syncUsername')));
    expect(settingKeys, isNot(contains('syncFakePassword')));
    expect(settingKeys, isNot(contains('syncRealPassword')));
    expect(settingKeys, isNot(contains('lastSyncTime')));
    expect(settingKeys, isNot(contains('lastServerSyncCursor')));
    expect(settingKeys, isNot(contains('deepseekApiKey')));
  });
}
