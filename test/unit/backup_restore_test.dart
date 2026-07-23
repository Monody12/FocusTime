import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = await Directory.systemTemp.createTemp(
      'focus_my_time_backup_test_',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
  });

  tearDownAll(() async {
    await AppDatabase.close();
    await databaseDirectory.delete(recursive: true);
  });

  Map<String, dynamic> cloneBackup(Map<String, dynamic> backup) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(backup)) as Map);
  }

  test('incomplete backup is rejected without changing current data', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: 'must survive invalid restore',
    );
    final backup = cloneBackup(await AppDatabase.exportBackup());
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    tables.remove('tasks');
    backup['tables'] = tables;

    await expectLater(
      AppDatabase.importBackup(backup),
      throwsA(isA<FormatException>()),
    );

    final unchanged = await AppDatabase.getTaskById(task['id'] as String);
    expect(unchanged?['title'], 'must survive invalid restore');
  });

  test('restore keeps local secrets and resets sync cursors', () async {
    final task = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: 'title in backup',
    );
    final taskId = task['id'] as String;
    final backup = cloneBackup(await AppDatabase.exportBackup());

    await AppDatabase.updateTask(taskId, {'title': 'newer local title'});
    await AppDatabase.setSetting('syncToken', 'device-token');
    await AppDatabase.setSetting('syncUserId', 'device-user');
    await AppDatabase.setSetting('deepseekApiKey', 'device-api-key');
    await AppDatabase.setSetting('lastSyncTime', '999');
    await AppDatabase.setSetting('lastServerSyncCursor', '888');

    await AppDatabase.importBackup(backup);

    final restored = await AppDatabase.getTaskById(taskId);
    expect(restored?['title'], 'title in backup');
    expect(await AppDatabase.getSetting('syncToken'), 'device-token');
    expect(await AppDatabase.getSetting('syncUserId'), 'device-user');
    expect(await AppDatabase.getSetting('deepseekApiKey'), 'device-api-key');
    expect(await AppDatabase.getSetting('lastSyncTime'), '0');
    expect(await AppDatabase.getSetting('lastServerSyncCursor'), '0');
  });

  test('backup without required system lists is rejected', () async {
    final backup = cloneBackup(await AppDatabase.exportBackup());
    final tables = Map<String, dynamic>.from(backup['tables'] as Map);
    final lists = List<Map<String, dynamic>>.from(
      (tables['lists'] as List).map(
        (row) => Map<String, dynamic>.from(row as Map),
      ),
    )..removeWhere((row) => row['id'] == 'system-my-day');
    tables['lists'] = lists;
    backup['tables'] = tables;

    await expectLater(
      AppDatabase.importBackup(backup),
      throwsA(isA<FormatException>()),
    );
  });
}
