import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('从 v13 升级时先创建备忘录表再执行 v16 隐私迁移', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir = await Directory.systemTemp.createTemp(
      'database_migration_test',
    );
    addTearDown(() async {
      await AppDatabase.close();
      await tempDir.delete(recursive: true);
    });
    await databaseFactory.setDatabasesPath(tempDir.path);
    final path = '${tempDir.path}${Platform.pathSeparator}focus_my_time.db';
    final legacy = await openDatabase(path, version: 13);
    await legacy.close();

    final upgraded = await AppDatabase.database;

    expect(await upgraded.getVersion(), 16);
    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memos'",
    );
    expect(tables, hasLength(1));
    final versionColumns = await upgraded.rawQuery(
      'PRAGMA table_info(memo_versions)',
    );
    expect(versionColumns.map((column) => column['name']), contains('source'));
  });
}
