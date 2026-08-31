import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Map<String, dynamic>> syncRecord(String table, String id) async {
    final payload = await AppDatabase.getSyncPayload(0);
    return payload[table]!.firstWhere((record) => record['id'] == id);
  }

  Map<String, dynamic> syncData(Map<String, dynamic> record) {
    return Map<String, dynamic>.from(record['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> rawRow(String table, String id) async {
    final db = await AppDatabase.database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    expect(rows, isNotEmpty);
    return rows.first;
  }

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
        },
      ],
    });

    final updatedTask = await AppDatabase.getTaskById(taskId);
    expect(updatedTask!['notes'], 'Android 应看到的备注');
    expect(updatedTask['calendarEventId'], 'calendar-event-1');

    await AppDatabase.archiveTask(taskId);
    expect(await AppDatabase.getTaskById(taskId), isNull);

    final archivedTasks = await AppDatabase.getArchivedTasks();
    final archivedTask = archivedTasks.firstWhere(
      (record) => record['id'] == taskId,
    );
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
    final baseData = Map<String, dynamic>.from(
      baseRecord['data'] as Map<String, dynamic>,
    );
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
        },
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

    final payload = await AppDatabase.getSyncPayload(originalUpdatedAt + 1);
    expect(
      payload['tasks']!.where((record) => record['id'] == taskId),
      isEmpty,
    );

    await AppDatabase.deleteTask(taskId);
  });

  test('普通任务更新里的本机日历事件 ID 不会推进任务同步时间戳', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '普通更新日历字段测试',
    );
    final taskId = task['id'] as String;
    final originalUpdatedAt = task['updatedAt'] as int;

    await AppDatabase.updateTask(taskId, {
      'calendarEventId': 'android-event-from-generic-update',
    });

    final updatedTask = await AppDatabase.getTaskById(taskId);
    expect(
      updatedTask!['calendarEventId'],
      'android-event-from-generic-update',
    );
    expect(updatedTask['updatedAt'], originalUpdatedAt);

    final payload = await AppDatabase.getSyncPayload(originalUpdatedAt + 1);
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

  test('清单归档和恢复会推进子任务归档字段版本', () async {
    final list = await AppDatabase.createList('字段版本清单');
    final listId = list['id'] as String;
    final task = await AppDatabase.createTask(
      listId: listId,
      title: '跟随清单归档的任务',
    );
    final taskId = task['id'] as String;

    final baseData = syncData(await syncRecord('tasks', taskId));
    final baseVersions = Map<String, dynamic>.from(
      baseData['_fieldUpdatedAt'] as Map,
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.archiveList(listId);

    final archivedData = syncData(await syncRecord('tasks', taskId));
    final archivedVersions = Map<String, dynamic>.from(
      archivedData['_fieldUpdatedAt'] as Map,
    );
    expect(archivedData['archived'], true);
    expect(archivedData['archivedAt'], isA<int>());
    expect(
      archivedVersions['archived'],
      greaterThan(baseVersions['archived'] as int),
    );
    expect(
      archivedVersions['archivedAt'],
      greaterThan(baseVersions['archivedAt'] as int),
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.restoreList(listId);

    final restoredData = syncData(await syncRecord('tasks', taskId));
    final restoredVersions = Map<String, dynamic>.from(
      restoredData['_fieldUpdatedAt'] as Map,
    );
    expect(restoredData['archived'], false);
    expect(restoredData['archivedAt'], isNull);
    expect(
      restoredVersions['archived'],
      greaterThan(archivedVersions['archived'] as int),
    );
    expect(
      restoredVersions['archivedAt'],
      greaterThan(archivedVersions['archivedAt'] as int),
    );

    await AppDatabase.deleteList(listId);
  });

  test('同批次先移动任务再归档旧清单时任务在新清单保持可见', () async {
    final oldList = await AppDatabase.createList('待归档旧清单');
    final newList = await AppDatabase.createList('新清单');
    final oldListId = oldList['id'] as String;
    final newListId = newList['id'] as String;
    final task = await AppDatabase.createTask(
      listId: oldListId,
      title: '跨清单移动任务',
    );
    final taskId = task['id'] as String;
    final oldListRecord = await syncRecord('lists', oldListId);
    final oldListData = syncData(oldListRecord);
    final taskRecord = await syncRecord('tasks', taskId);
    final taskData = syncData(taskRecord);
    final taskVersions = Map<String, dynamic>.from(
      taskData['_fieldUpdatedAt'] as Map,
    );
    final moveAt = (taskRecord['updatedAt'] as int) + 100;
    final archiveAt = moveAt + 100;

    await AppDatabase.applySyncChanges({
      'lists': [
        {
          'id': oldListId,
          'updatedAt': archiveAt,
          'deleted': false,
          'data': {
            ...oldListData,
            'archived': true,
            'archivedAt': archiveAt,
            'updatedAt': archiveAt,
          },
        },
      ],
      'tasks': [
        {
          'id': taskId,
          'updatedAt': moveAt,
          'deleted': false,
          'data': {
            ...taskData,
            'listId': newListId,
            'updatedAt': moveAt,
            '_fieldUpdatedAt': {...taskVersions, 'listId': moveAt},
          },
        },
      ],
    });

    final movedTask = await AppDatabase.getTaskById(taskId);
    expect(movedTask, isNotNull);
    expect(movedTask!['listId'], newListId);
    expect(movedTask['archived'], false);
    expect(
      (await AppDatabase.getTasksByList(newListId)).map((item) => item['id']),
      contains(taskId),
    );

    await AppDatabase.deleteList(oldListId);
    await AppDatabase.deleteList(newListId);
  });

  test('已同步的错误归档状态会自动恢复并生成增量修复记录', () async {
    final oldList = await AppDatabase.createList('历史归档清单');
    final newList = await AppDatabase.createList('历史目标清单');
    final oldListId = oldList['id'] as String;
    final newListId = newList['id'] as String;
    final task = await AppDatabase.createTask(
      listId: oldListId,
      title: '历史错乱任务',
    );
    final taskId = task['id'] as String;
    final oldListRecord = await syncRecord('lists', oldListId);
    final oldListData = syncData(oldListRecord);
    final taskRecord = await syncRecord('tasks', taskId);
    final taskData = syncData(taskRecord);
    final taskVersions = Map<String, dynamic>.from(
      taskData['_fieldUpdatedAt'] as Map,
    );
    final moveAt = (taskRecord['updatedAt'] as int) + 100;
    final archiveAt = moveAt + 100;
    final renamedAt = archiveAt + 100;

    await AppDatabase.applySyncChanges({
      'lists': [
        {
          'id': oldListId,
          'updatedAt': archiveAt,
          'deleted': false,
          'data': {
            ...oldListData,
            'archived': true,
            'archivedAt': archiveAt,
            'updatedAt': archiveAt,
          },
        },
      ],
      'tasks': [
        {
          'id': taskId,
          'updatedAt': renamedAt,
          'deleted': false,
          'data': {
            ...taskData,
            'listId': newListId,
            'title': '改名后仍不可见的任务',
            'archived': true,
            'archivedAt': archiveAt,
            'updatedAt': renamedAt,
            '_fieldUpdatedAt': {
              ...taskVersions,
              'listId': moveAt,
              'title': renamedAt,
              'archived': archiveAt,
              'archivedAt': archiveAt,
            },
          },
        },
      ],
    });

    final repairedTask = await AppDatabase.getTaskById(taskId);
    expect(repairedTask, isNotNull);
    expect(repairedTask!['listId'], newListId);
    expect(repairedTask['title'], '改名后仍不可见的任务');
    expect(repairedTask['archived'], false);
    expect(repairedTask['archivedAt'], isNull);

    final repairPayload = await AppDatabase.getSyncPayload(renamedAt);
    final repairRecord = repairPayload['tasks']!.firstWhere(
      (item) => item['id'] == taskId,
    );
    final repairData = syncData(repairRecord);
    final repairVersions = Map<String, dynamic>.from(
      repairData['_fieldUpdatedAt'] as Map,
    );
    expect(repairData['archived'], false);
    expect(repairData['archivedAt'], isNull);
    expect(repairVersions['archived'], greaterThan(archiveAt));
    expect(repairVersions['archivedAt'], greaterThan(archiveAt));

    await AppDatabase.deleteList(oldListId);
    await AppDatabase.deleteList(newListId);
  });

  test('Schema 12 升级到最新版本时会恢复本机已有的错误归档任务', () async {
    final oldList = await AppDatabase.createList('迁移旧清单');
    final newList = await AppDatabase.createList('迁移目标清单');
    final oldListId = oldList['id'] as String;
    final newListId = newList['id'] as String;
    final task = await AppDatabase.createTask(
      listId: oldListId,
      title: '迁移恢复任务',
    );
    final taskId = task['id'] as String;
    final moveAt = (task['updatedAt'] as int) + 100;
    final archiveAt = moveAt + 100;
    final corruptedUpdatedAt = archiveAt + 100;
    final db = await AppDatabase.database;

    await db.transaction((txn) async {
      await txn.update(
        'lists',
        {'archived': 1, 'archived_at': archiveAt, 'updated_at': archiveAt},
        where: 'id = ?',
        whereArgs: [oldListId],
      );
      await txn.update(
        'tasks',
        {
          'list_id': newListId,
          'archived': 1,
          'archived_at': archiveAt,
          'updated_at': corruptedUpdatedAt,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      for (final entry in {
        'listId': moveAt,
        'archived': archiveAt,
        'archivedAt': archiveAt,
      }.entries) {
        await txn.insert('sync_field_versions', {
          'table_name': 'tasks',
          'record_id': taskId,
          'field_name': entry.key,
          'updated_at': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await db.setVersion(12);
    await AppDatabase.close();

    final upgradedDb = await AppDatabase.database;
    expect(await upgradedDb.getVersion(), 16);
    final repairedTask = await AppDatabase.getTaskById(taskId);
    expect(repairedTask, isNotNull);
    expect(repairedTask!['listId'], newListId);
    expect(repairedTask['archived'], false);
    expect(repairedTask['archivedAt'], isNull);

    final repairPayload = await AppDatabase.getSyncPayload(corruptedUpdatedAt);
    final repairRecord = repairPayload['tasks']!.firstWhere(
      (item) => item['id'] == taskId,
    );
    final repairData = syncData(repairRecord);
    final repairVersions = Map<String, dynamic>.from(
      repairData['_fieldUpdatedAt'] as Map,
    );
    expect(repairVersions['archived'], greaterThan(archiveAt));
    expect(repairVersions['archivedAt'], greaterThan(archiveAt));

    await AppDatabase.deleteList(oldListId);
    await AppDatabase.deleteList(newListId);
  });

  test('任务修改后撤销只需增量同步最终字段状态', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '撤销前标题',
    );
    final taskId = task['id'] as String;
    final baseline = task['updatedAt'] as int;

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.updateTask(taskId, {'title': '临时标题'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.updateTask(taskId, {'title': '撤销前标题'});

    final payload = await AppDatabase.getSyncPayload(baseline);
    final changedTasks = payload['tasks']!.where(
      (item) => item['id'] == taskId,
    );
    expect(changedTasks, hasLength(1));
    final revertedData = syncData(changedTasks.single);
    final versions = Map<String, dynamic>.from(
      revertedData['_fieldUpdatedAt'] as Map,
    );
    expect(revertedData['title'], '撤销前标题');
    expect(versions['title'], greaterThan(baseline));

    await AppDatabase.deleteTask(taskId);
  });

  test('增量同步包含恰好落在同步水位毫秒的任务变更', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '水位边界任务',
    );
    final taskId = task['id'] as String;
    final updatedAt = task['updatedAt'] as int;
    final payload = await AppDatabase.getSyncPayload(updatedAt);
    expect(
      payload['tasks']!.where((record) => record['id'] == taskId),
      hasLength(1),
    );

    await AppDatabase.deleteTask(taskId);
  });

  test('远端任务删除会保留本地墓碑并继续进入同步负载', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '远端删除墓碑任务',
    );
    final taskId = task['id'] as String;
    final record = await syncRecord('tasks', taskId);
    final data = syncData(record);
    final remoteDeletedAt = (record['updatedAt'] as int) + 10;

    await AppDatabase.applySyncChanges({
      'tasks': [
        {
          'id': taskId,
          'updatedAt': remoteDeletedAt,
          'deleted': true,
          'data': {...data, 'updatedAt': remoteDeletedAt, 'deleted': true},
        },
      ],
    });

    expect(await AppDatabase.getTaskById(taskId), isNull);
    final row = await rawRow('tasks', taskId);
    expect(row['deleted'], 1);

    final payload = await AppDatabase.getSyncPayload(remoteDeletedAt + 1);
    final tombstone = payload['tasks']!.firstWhere(
      (item) => item['id'] == taskId,
    );
    expect(tombstone['deleted'], true);
  });

  test('远端任务删除优先于本地较新未删除更新', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '本地较新但应被删除',
    );
    final taskId = task['id'] as String;
    final baseRecord = await syncRecord('tasks', taskId);
    final baseData = syncData(baseRecord);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.updateTask(taskId, {'title': '本地较新标题'});
    final localRow = await rawRow('tasks', taskId);
    final localUpdatedAt = localRow['updated_at'] as int;
    final remoteDeletedAt = localUpdatedAt - 1;

    await AppDatabase.applySyncChanges({
      'tasks': [
        {
          'id': taskId,
          'updatedAt': remoteDeletedAt,
          'deleted': true,
          'data': {...baseData, 'updatedAt': remoteDeletedAt, 'deleted': true},
        },
      ],
    });

    expect(await AppDatabase.getTaskById(taskId), isNull);
    final deletedRow = await rawRow('tasks', taskId);
    expect(deletedRow['deleted'], 1);
    expect(deletedRow['updated_at'], localUpdatedAt);
  });

  test('本地任务墓碑不会被远端较新非删除记录复活', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: '禁止复活任务',
    );
    final taskId = task['id'] as String;
    final record = await syncRecord('tasks', taskId);
    final data = syncData(record);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AppDatabase.deleteTask(taskId);
    final deletedRow = await rawRow('tasks', taskId);
    final remoteUpdatedAt = (deletedRow['updated_at'] as int) + 100;

    await AppDatabase.applySyncChanges({
      'tasks': [
        {
          'id': taskId,
          'updatedAt': remoteUpdatedAt,
          'deleted': false,
          'data': {
            ...data,
            'title': '远端复活标题',
            'updatedAt': remoteUpdatedAt,
            'deleted': false,
          },
        },
      ],
    });

    expect(await AppDatabase.getTaskById(taskId), isNull);
    final row = await rawRow('tasks', taskId);
    expect(row['deleted'], 1);
    expect(row['title'], '禁止复活任务');
  });

  test('远端清单归档会防御性级联归档本地子任务', () async {
    final list = await AppDatabase.createList('远端归档清单');
    final listId = list['id'] as String;
    final task = await AppDatabase.createTask(listId: listId, title: '应随清单归档');
    final taskId = task['id'] as String;
    final listRecord = await syncRecord('lists', listId);
    final listData = syncData(listRecord);
    final taskDataBeforeArchive = syncData(await syncRecord('tasks', taskId));
    final taskVersionsBeforeArchive = Map<String, dynamic>.from(
      taskDataBeforeArchive['_fieldUpdatedAt'] as Map,
    );
    final remoteArchivedAt =
        [
          listRecord['updatedAt'] as int,
          taskVersionsBeforeArchive['archived'] as int,
          taskVersionsBeforeArchive['archivedAt'] as int,
        ].reduce((a, b) => a > b ? a : b) +
        20;

    await AppDatabase.applySyncChanges({
      'lists': [
        {
          'id': listId,
          'updatedAt': remoteArchivedAt,
          'deleted': false,
          'data': {
            ...listData,
            'archived': true,
            'archivedAt': remoteArchivedAt,
            'updatedAt': remoteArchivedAt,
          },
        },
      ],
    });

    expect(await AppDatabase.getTasksByList(listId), isEmpty);
    final archivedTasks = await AppDatabase.getArchivedTasks(
      excludeTasksInArchivedLists: false,
    );
    expect(archivedTasks.any((item) => item['id'] == taskId), true);
    final taskData = syncData(await syncRecord('tasks', taskId));
    final versions = Map<String, dynamic>.from(
      taskData['_fieldUpdatedAt'] as Map,
    );
    expect(taskData['archived'], true);
    expect(versions['archived'], remoteArchivedAt);
  });

  test('远端清单删除会防御性级联软删除本地子任务和会话', () async {
    final list = await AppDatabase.createList('远端删除清单');
    final listId = list['id'] as String;
    final task = await AppDatabase.createTask(listId: listId, title: '应随清单删除');
    final taskId = task['id'] as String;
    final session = await AppDatabase.addFocusSession(
      taskId: taskId,
      taskTitle: '应随清单删除',
      timerMode: 'single',
      durationSeconds: 60,
      plannedDurationSeconds: 60,
      completed: true,
      startedAt: DateTime(2026, 7, 4, 9).millisecondsSinceEpoch,
      completedAt: DateTime(2026, 7, 4, 9, 1).millisecondsSinceEpoch,
    );
    final sessionId = session['id'] as String;
    final listRecord = await syncRecord('lists', listId);
    final listData = syncData(listRecord);
    final remoteDeletedAt = (listRecord['updatedAt'] as int) + 20;

    await AppDatabase.applySyncChanges({
      'lists': [
        {
          'id': listId,
          'updatedAt': remoteDeletedAt,
          'deleted': true,
          'data': {...listData, 'updatedAt': remoteDeletedAt, 'deleted': true},
        },
      ],
    });

    expect(await AppDatabase.getTasksByList(listId), isEmpty);
    expect((await rawRow('lists', listId))['deleted'], 1);
    expect((await rawRow('tasks', taskId))['deleted'], 1);
    expect((await rawRow('sessions', sessionId))['deleted'], 1);
  });

  test('清单置顶、图标和隐藏字段会进入同步负载并可应用远端变更', () async {
    final list = await AppDatabase.createList('置顶同步清单');
    final listId = list['id'] as String;

    await AppDatabase.updateListCustomization(
      listId,
      iconKey: 'work',
      pinned: true,
      topOrder: 3,
      hidden: false,
    );

    final listRecord = await syncRecord('lists', listId);
    final data = syncData(listRecord);
    expect(data['iconKey'], 'work');
    expect(data['pinned'], true);
    expect(data['topOrder'], 3);
    expect(data['hidden'], false);

    final remoteUpdatedAt = (listRecord['updatedAt'] as int) + 10;
    await AppDatabase.applySyncChanges({
      'lists': [
        {
          'id': listId,
          'updatedAt': remoteUpdatedAt,
          'deleted': false,
          'data': {
            ...data,
            'iconKey': 'book',
            'pinned': false,
            'topOrder': null,
            'hidden': true,
            'updatedAt': remoteUpdatedAt,
          },
        },
      ],
    });

    final rows = await AppDatabase.getLists();
    final updated = rows.firstWhere((item) => item['id'] == listId);
    expect(updated['iconKey'], 'book');
    expect(updated['pinned'], false);
    expect(updated['topOrder'], isNull);
    expect(updated['hidden'], true);

    await AppDatabase.deleteList(listId);
  });

  test('自动归档同一清单内超出保留数量的已完成同名任务', () async {
    final list = await AppDatabase.createList('自动归档清单');
    final listId = list['id'] as String;
    final taskIds = <String>[];

    for (var i = 0; i < 5; i++) {
      final task = await AppDatabase.createTask(listId: listId, title: '重复完成项');
      final taskId = task['id'] as String;
      taskIds.add(taskId);
      await AppDatabase.toggleTaskComplete(taskId);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    final archivedCount = await AppDatabase.autoArchiveCompletedTasks(
      keepCount: 3,
    );
    expect(archivedCount, 2);

    final activeTasks = await AppDatabase.getTasksByList(listId);
    expect(
      activeTasks
          .where(
            (item) => item['title'] == '重复完成项' && item['completed'] == true,
          )
          .length,
      3,
    );
    final archivedTasks = await AppDatabase.getArchivedTasks();
    expect(
      archivedTasks.where((item) => taskIds.contains(item['id'])).length,
      2,
    );

    await AppDatabase.deleteList(listId);
  });
}
