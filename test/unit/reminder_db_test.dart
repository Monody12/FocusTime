import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:focus_my_time/data/database/app_database.dart';

void main() {
  // 初始化 FFI 数据库 Factory
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('数据库提醒字段验证测试', () async {
    // 1. 创建名为 "test" 的任务
    final result = await AppDatabase.createTask(
      listId: 'system-all-tasks',
      title: 'test',
    );
    final taskId = result['id'];

    // 2. 设置提醒时间 (模拟 2026年5月7日 18:00:00)
    final reminderTime = DateTime(2026, 5, 7, 18).millisecondsSinceEpoch;
    await AppDatabase.updateTask(taskId, {'reminderAt': reminderTime});

    // 3. 从数据库重新读取并验证
    final dbTask = await AppDatabase.getTaskById(taskId);

    expect(dbTask, isNotNull, reason: '数据库中应存在该任务');
    expect(dbTask!['title'], 'test', reason: '任务标题应为 test');
    expect(dbTask['reminderAt'], reminderTime, reason: '提醒时间戳应与设置值完全一致');

    // 清理测试数据
    await AppDatabase.deleteTask(taskId);
  });
}
