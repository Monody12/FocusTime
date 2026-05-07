import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';

void main() {
  test('Clear database for sync testing', () async {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'focus_my_time.db');
    
    print('DATABASE_PATH: $path');
    
    if (!await File(path).exists()) {
      print('Database file does not exist at $path');
      return;
    }

    final db = await databaseFactory.openDatabase(path);
    
    await db.transaction((txn) async {
      print('Deleting records...');
      await txn.delete('tasks');
      await txn.delete('sessions');
      await txn.delete('task_recurrence_completions');
      
      // Keep system lists but clear custom ones
      await txn.delete('lists', where: 'is_system = 0');
      
      // Keep sync settings but reset lastSyncTime
      await txn.update('settings', {'value': '0'}, where: 'key = ?', whereArgs: ['lastSyncTime']);
      
      print('Records deleted.');
    });
    
    await db.close();
    print('SUCCESS: Database cleared.');
  });
}
