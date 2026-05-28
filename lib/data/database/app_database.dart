import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:io';

class AppDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 关闭数据库连接，重置单例缓存
  /// 导入/导出前必须调用，否则文件句柄锁定会导致复制失败
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// 导出数据库到指定路径
  ///
  /// 流程：WAL checkpoint（将 WAL 日志合并到主库）→ 关闭连接 → 复制文件 → 重新打开
  /// 如果不执行 checkpoint，WAL 中已提交的事务会丢失，备份不完整
  static Future<void> exportDatabase(String outputPath) async {
    final sourcePath = await getDbPath();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('数据库文件不存在: $sourcePath');
    }

    final db = await database;
    try {
      // 将 WAL 日志中的已提交事务写回主数据库文件
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // 部分 SQLite 配置未启用 WAL 模式，checkpoint 会失败，可安全忽略
    }

    // 必须关闭连接才能安全复制数据库文件
    await close();
    try {
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await sourceFile.copy(outputPath);
    } finally {
      // 无论复制成功与否，都重新打开数据库供应用继续使用
      await database;
    }
  }

  /// 从备份文件导入恢复数据库
  ///
  /// 流程：校验备份 → 关闭连接 → 清理 sidecar 文件 → 覆盖主库 → 清理 sidecar → 重新打开
  /// 导入后调用方需重新加载任务列表和提醒调度
  static Future<void> importDatabase(String backupPath) async {
    await validateBackupFile(backupPath);

    final dbPath = await getDbPath();
    await close();
    // 删除旧的 WAL/SHM/journal，防止旧的 sidecar 文件干扰新数据库
    await _deleteDatabaseSidecars(dbPath);

    try {
      await File(backupPath).copy(dbPath);
      // 删除备份文件可能带来的 sidecar（如果备份时 WAL 未 checkpoint）
      await _deleteDatabaseSidecars(dbPath);
      await database;
    } catch (e) {
      // 导入失败时重置单例，下次访问会重新初始化
      _database = null;
      rethrow;
    }
  }

  /// 校验备份文件的完整性
  ///
  /// 检查项：
  /// 1. 文件是否存在
  /// 2. 数据库版本号是否在支持范围内（≤ 当前版本 9）
  /// 3. 必要的数据表是否存在（lists, tasks, sessions, settings）
  static Future<void> validateBackupFile(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('备份文件不存在');
    }

    Database? backupDb;
    try {
      // 以只读模式打开备份文件进行校验，不修改原始备份
      backupDb = await openDatabase(backupPath, readOnly: true);
      final version = await backupDb.getVersion();
      if (version > 9) {
        throw Exception('备份数据库版本过高: $version');
      }

      final tableRows = await backupDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows.map((row) => row['name'] as String).toSet();
      const requiredTables = {'lists', 'tasks', 'sessions', 'settings'};
      final missingTables = requiredTables.difference(tables);
      if (missingTables.isNotEmpty) {
        throw Exception('备份文件缺少必要数据表: ${missingTables.join(', ')}');
      }
    } finally {
      await backupDb?.close();
    }
  }

  /// 删除数据库的 WAL、SHM 和 journal 附属文件
  /// 这些文件在 SQLite WAL 模式下自动生成，导入/导出时需要清理以确保一致性
  static Future<void> _deleteDatabaseSidecars(String dbPath) async {
    for (final path in ['$dbPath-wal', '$dbPath-shm', '$dbPath-journal']) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'focus_my_time.db');

    return await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        list_id TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
        completed INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER,
        due_date TEXT,
        due_time TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_my_day INTEGER NOT NULL DEFAULT 0,
        my_day_added_at INTEGER,
        recurrence_config TEXT,
        expected_minutes INTEGER,
        is_important INTEGER NOT NULL DEFAULT 0,
        reminder_at INTEGER,
        calendar_event_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        task_title TEXT NOT NULL,
        timer_mode TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        planned_duration_seconds INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE task_recurrence_completions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        completion_date TEXT NOT NULL,
        completed_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(task_id, completion_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        tool_calls_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_operations (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT NOT NULL,
        params_json TEXT NOT NULL,
        summary TEXT NOT NULL,
        reasoning TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 加速提醒查询的复合索引
    await db.execute('CREATE INDEX idx_tasks_reminders ON tasks(deleted, completed, reminder_at)');

    // 种子数据
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('lists', {
      'id': 'system-my-day',
      'name': '我的一天',
      'is_system': 1,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('lists', {
      'id': 'system-important',
      'name': '重要',
      'is_system': 1,
      'sort_order': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('lists', {
      'id': 'system-all-tasks',
      'name': '任务',
      'is_system': 1,
      'sort_order': 2,
      'created_at': now,
      'updated_at': now,
    });
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 增加删除标记位以支持同步
      await db.execute('ALTER TABLE lists ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE tasks ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE sessions ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE task_recurrence_completions ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
    }
    
    if (oldVersion < 3) {
      // 为设置表增加时间戳以支持同步
      try {
        await db.execute('ALTER TABLE settings ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        // Ignore if column already exists
      }
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN is_important INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        // Ignore if column already exists
      }
    }

    if (oldVersion < 5) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('lists', {
        'id': 'system-important',
        'name': '重要',
        'is_system': 1,
        'sort_order': 1,
        'created_at': now,
        'updated_at': now,
      });
      await db.execute("UPDATE lists SET sort_order = sort_order + 1 WHERE id = 'system-all-tasks'");
    }

    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN reminder_at INTEGER');
      } catch (e) {
        // Ignore if column already exists
      }
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN calendar_event_id TEXT');
      } catch (e) {
        // Ignore if column already exists
      }
    }

    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_conversations (
          id TEXT PRIMARY KEY,
          title TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          tool_calls_json TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_operations (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          type TEXT NOT NULL,
          params_json TEXT NOT NULL,
          summary TEXT NOT NULL,
          reasoning TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 9) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_reminders ON tasks(deleted, completed, reminder_at)');
    }
  }

  // ========== 设置 ==========

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key, 
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== 清单 ==========

  static Future<List<Map<String, dynamic>>> getLists() async {
    final db = await database;
    final result = await db.query('lists', where: 'deleted = 0', orderBy: 'sort_order');
    return result.map(_mapList).toList();
  }

  /// 将数据库行映射为应用程序使用的 TaskList 对象，并处理命名格式转换（snake_case -> camelCase）
  static Map<String, dynamic> _mapList(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'name': row['name'],
      // 数据库存储为 0/1，这里转换为布尔值
      'isSystem': (row['is_system'] as int) == 1,
      'sortOrder': row['sort_order'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'deleted': (row['deleted'] as int) == 1,
    };
  }

  static Future<Map<String, dynamic>> createList(String name) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM lists')) ?? 0;
    final id = 'list-${DateTime.now().millisecondsSinceEpoch}';

    await db.insert('lists', {
      'id': id,
      'name': name,
      'is_system': 0,
      'sort_order': count,
      'created_at': now,
      'updated_at': now,
    });

    return {
      'id': id,
      'name': name,
      'isSystem': false,
      'sortOrder': count,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  static Future<void> updateList(String id, String name) async {
    final db = await database;
    await db.update('lists', {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 软删除清单及其下的所有任务
  static Future<void> deleteList(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的任务，防止更新已删除记录的 updated_at 导致重复同步
    await db.update('tasks', {'deleted': 1, 'updated_at': now},
        where: 'list_id = ? AND deleted = 0', whereArgs: [id]);
    await db.update('lists', {'deleted': 1, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
  }

  // ========== 任务 ==========

  static Future<Map<String, dynamic>?> getTaskById(String id) async {
    final db = await database;
    // 过滤已删除任务，防止调用方操作已被软删除的僵尸任务
    final result = await db.query('tasks', where: 'id = ? AND deleted = 0', whereArgs: [id]);
    if (result.isEmpty) return null;
    return _mapTask(result.first);
  }

  static Future<List<Map<String, dynamic>>> getTasksByList(String listId) async {
    final db = await database;
    final result = await db.query('tasks',
        where: 'list_id = ? AND deleted = 0', whereArgs: [listId], orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getMyDayTasks() async {
    final db = await database;
    final result = await db.query('tasks',
        where: 'is_my_day = 1 AND deleted = 0', orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getImportantTasks() async {
    final db = await database;
    final result = await db.query('tasks',
        where: 'is_important = 1 AND deleted = 0', orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    final result = await db.query('tasks', where: 'deleted = 0', orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  /// 获取所有有待处理提醒的未完成任务（仅返回未来的提醒）
  static Future<List<Map<String, dynamic>>> getActiveReminders() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await db.query('tasks',
        where: 'deleted = 0 AND completed = 0 AND reminder_at IS NOT NULL AND reminder_at > ?',
        whereArgs: [now],
        orderBy: 'reminder_at');
    return result.map(_mapTask).toList();
  }

  static Future<Map<String, dynamic>> createTask({
    required String listId,
    required String title,
    String? notes,
    String? dueDate,
    String? dueTime,
    bool isMyDay = false,
    int? expectedMinutes,
    int? reminderAt,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM tasks WHERE list_id = ?', [listId])) ?? 0;
    final id = 'task-${DateTime.now().millisecondsSinceEpoch}';

    await db.insert('tasks', {
      'id': id,
      'list_id': listId,
      'title': title,
      'notes': notes,
      'completed': 0,
      'completed_at': null,
      'due_date': dueDate,
      'due_time': dueTime,
      'sort_order': count,
      'is_my_day': isMyDay ? 1 : 0,
      'my_day_added_at': isMyDay ? now : null,
      'recurrence_config': null,
      'expected_minutes': expectedMinutes,
      'is_important': 0,
      'reminder_at': reminderAt,
      'calendar_event_id': null,
      'created_at': now,
      'updated_at': now,
    });

    return {
      'id': id,
      'listId': listId,
      'title': title,
      'notes': notes,
      'completed': false,
      'completedAt': null,
      'dueDate': dueDate,
      'dueTime': dueTime,
      'sortOrder': count,
      'isMyDay': isMyDay,
      'myDayAddedAt': isMyDay ? now : null,
      'recurrenceConfig': null,
      'expectedMinutes': expectedMinutes,
      'isImportant': false,
      'reminderAt': reminderAt,
      'calendarEventId': null,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  static Future<void> updateTask(String id, Map<String, dynamic> updates) async {
    final db = await database;
    final mapped = <String, dynamic>{};

    if (updates.containsKey('title')) mapped['title'] = updates['title'];
    if (updates.containsKey('notes')) mapped['notes'] = updates['notes'];
    if (updates.containsKey('listId')) mapped['list_id'] = updates['listId'];
    if (updates.containsKey('dueDate')) mapped['due_date'] = updates['dueDate'];
    if (updates.containsKey('dueTime')) mapped['due_time'] = updates['dueTime'];
    if (updates.containsKey('sortOrder')) mapped['sort_order'] = updates['sortOrder'];
    if (updates.containsKey('isMyDay')) mapped['is_my_day'] = updates['isMyDay'] ? 1 : 0;
    if (updates.containsKey('myDayAddedAt')) mapped['my_day_added_at'] = updates['myDayAddedAt'];
    if (updates.containsKey('completed')) mapped['completed'] = updates['completed'] ? 1 : 0;
    if (updates.containsKey('completedAt')) mapped['completed_at'] = updates['completedAt'];
    if (updates.containsKey('recurrenceConfig')) {
      final config = updates['recurrenceConfig'];
      mapped['recurrence_config'] = config != null ? _encodeJson(config) : null;
    }
    if (updates.containsKey('expectedMinutes')) {
      mapped['expected_minutes'] = updates['expectedMinutes'];
    }
    if (updates.containsKey('isImportant')) {
      mapped['is_important'] = updates['isImportant'] ? 1 : 0;
    }
    if (updates.containsKey('reminderAt')) {
      mapped['reminder_at'] = updates['reminderAt'];
    }
    if (updates.containsKey('calendarEventId')) {
      mapped['calendar_event_id'] = updates['calendarEventId'];
    }

    mapped['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    mapped['id'] = id;

    final sets = mapped.keys.where((k) => k != 'id').map((k) => '$k = ?').join(', ');
    final values = mapped.keys.where((k) => k != 'id').map((k) => mapped[k]).toList();

    // 仅更新未删除的任务，防止操作已被软删除的僵尸记录
    await db.rawUpdate('UPDATE tasks SET $sets WHERE id = ? AND deleted = 0', [...values, id]);
  }

  /// 软删除任务及其下的所有会话
  static Future<void> deleteTask(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的会话，防止更新已删除记录的 updated_at 导致重复同步
    await db.update('sessions', {'deleted': 1, 'updated_at': now},
        where: 'task_id = ? AND deleted = 0', whereArgs: [id]);
    await db.update('tasks', {'deleted': 1, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> toggleTaskComplete(String id) async {
    final db = await database;
    // 仅查询未删除的任务，避免对已删除的僵尸任务进行操作
    final result = await db.query('tasks', columns: ['completed'],
        where: 'id = ? AND deleted = 0', whereArgs: [id]);
    if (result.isEmpty) return;

    final currentCompleted = result.first['completed'] as int;
    final newCompleted = currentCompleted == 1 ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update('tasks', {
      'completed': newCompleted,
      'completed_at': newCompleted == 1 ? now : null,
      'updated_at': now,
    }, where: 'id = ? AND deleted = 0', whereArgs: [id]);
  }

  static Future<void> addToMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的任务
    await db.update('tasks', {
      'is_my_day': 1,
      'my_day_added_at': now,
      'updated_at': now,
    }, where: 'id = ? AND deleted = 0', whereArgs: [taskId]);
  }

  static Future<void> removeFromMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的任务
    await db.update('tasks', {
      'is_my_day': 0,
      'my_day_added_at': null,
      'updated_at': now,
    }, where: 'id = ? AND deleted = 0', whereArgs: [taskId]);
  }

  static Future<void> reorderTasks(List<String> taskIds) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < taskIds.length; i++) {
      batch.update('tasks', {'sort_order': i, 'updated_at': now},
          where: 'id = ?', whereArgs: [taskIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> reorderLists(List<String> listIds, {int offset = 0}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < listIds.length; i++) {
      batch.update('lists', {'sort_order': i + offset, 'updated_at': now},
          where: 'id = ?', whereArgs: [listIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  // ========== 专注会话 ==========

  static Future<Map<String, dynamic>> addFocusSession({
    String? taskId,
    required String taskTitle,
    required String timerMode,
    required int durationSeconds,
    required int plannedDurationSeconds,
    required bool completed,
    required int startedAt,
    int? completedAt,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'session-${DateTime.now().millisecondsSinceEpoch}';

    await db.insert('sessions', {
      'id': id,
      'task_id': taskId,
      'task_title': taskTitle,
      'timer_mode': timerMode,
      'duration_seconds': durationSeconds,
      'planned_duration_seconds': plannedDurationSeconds,
      'completed': completed ? 1 : 0,
      'started_at': startedAt,
      'completed_at': completedAt,
      'updated_at': now,
    });

    return {
      'id': id,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'timerMode': timerMode,
      'durationSeconds': durationSeconds,
      'plannedDurationSeconds': plannedDurationSeconds,
      'completed': completed,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'updatedAt': now,
    };
  }

  static Future<List<Map<String, dynamic>>> getSessionsByDate(String date) async {
    final db = await database;
    final start = DateTime.parse('$date 00:00:00').millisecondsSinceEpoch;
    final end = DateTime.parse('$date 23:59:59').millisecondsSinceEpoch;
    final result = await db.query('sessions',
        where: 'started_at BETWEEN ? AND ? AND deleted = 0', whereArgs: [start, end]);
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByDateRange(
      String startDate, String endDate) async {
    final db = await database;
    final start = DateTime.parse('$startDate 00:00:00').millisecondsSinceEpoch;
    final end = DateTime.parse('$endDate 23:59:59').millisecondsSinceEpoch;
    final result = await db.query('sessions',
        where: 'started_at BETWEEN ? AND ? AND deleted = 0', 
        whereArgs: [start, end], orderBy: 'started_at');
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByTaskId(String taskId) async {
    final db = await database;
    // 过滤已删除的会话，避免在任务详情中显示无效的专注记录
    final result = await db.query('sessions',
        where: 'task_id = ? AND deleted = 0', whereArgs: [taskId], orderBy: 'started_at DESC');
    return result.map(_mapSession).toList();
  }

  // ========== 重复完成记录 ==========

  static Future<bool> toggleRecurrenceCompletion(String taskId, String date) async {
    final db = await database;
    final existing = await db.query('task_recurrence_completions',
        where: 'task_id = ? AND completion_date = ?', whereArgs: [taskId, date]);

    if (existing.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update('task_recurrence_completions', 
          {'deleted': 1, 'updated_at': now},
          where: 'id = ?', whereArgs: [existing.first['id']]);
      return false;
    } else {
      final id = 'rc-${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('task_recurrence_completions', {
        'id': id,
        'task_id': taskId,
        'completion_date': date,
        'completed_at': now,
        'created_at': now,
        'updated_at': now,
      });
      return true;
    }
  }

  static Future<List<Map<String, dynamic>>> getRecurrenceCompletions(String taskId) async {
    final db = await database;
    final result = await db.query('task_recurrence_completions',
        where: 'task_id = ? AND deleted = 0', whereArgs: [taskId], orderBy: 'completion_date DESC');
    return result.map(_mapRecurrenceCompletion).toList();
  }

  static Future<List<Map<String, dynamic>>> getRecurrenceCompletionsByDateRange(
      String taskId, String startDate, String endDate) async {
    final db = await database;
    // 过滤已删除的完成记录
    final result = await db.query('task_recurrence_completions',
        where: 'task_id = ? AND completion_date BETWEEN ? AND ? AND deleted = 0',
        whereArgs: [taskId, startDate, endDate],
        orderBy: 'completion_date DESC');
    return result.map(_mapRecurrenceCompletion).toList();
  }

  // ========== 辅助方法 ==========

  static Map<String, dynamic> _mapTask(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'listId': row['list_id'],
      'title': row['title'],
      'notes': row['notes'],
      'completed': (row['completed'] as int) == 1,
      'completedAt': row['completed_at'],
      'dueDate': row['due_date'],
      'dueTime': row['due_time'],
      'sortOrder': row['sort_order'],
      'isMyDay': (row['is_my_day'] as int) == 1,
      'myDayAddedAt': row['my_day_added_at'],
      'recurrenceConfig': row['recurrence_config'] != null
          ? _decodeJson(row['recurrence_config'] as String)
          : null,
      'expectedMinutes': row['expected_minutes'],
      'isImportant': (row['is_important'] as int) == 1,
      'reminderAt': row['reminder_at'],
      'calendarEventId': row['calendar_event_id'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'deleted': (row['deleted'] as int) == 1,
    };
  }

  static Map<String, dynamic> _mapSession(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'taskId': row['task_id'],
      'taskTitle': row['task_title'],
      'timerMode': row['timer_mode'],
      'durationSeconds': row['duration_seconds'],
      'plannedDurationSeconds': row['planned_duration_seconds'],
      'completed': (row['completed'] as int) == 1,
      'startedAt': row['started_at'],
      'completedAt': row['completed_at'],
      'updatedAt': row['updated_at'],
      'deleted': (row['deleted'] as int) == 1,
    };
  }

  static Map<String, dynamic> _mapRecurrenceCompletion(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'taskId': row['task_id'],
      'completionDate': row['completion_date'],
      'completedAt': row['completed_at'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'deleted': (row['deleted'] as int) == 1,
    };
  }

  // ========== 同步支持 ==========

  /// 获取自上次同步以来发生变更的所有记录
  static Future<Map<String, List<Map<String, dynamic>>>> getSyncPayload(int lastSyncTime) async {
    final db = await database;
    final payload = <String, List<Map<String, dynamic>>>{};

    // 获取各表的变更记录
    payload['lists'] = await _getSyncTableRecords(db, 'lists', lastSyncTime, _mapList);
    payload['tasks'] = await _getSyncTableRecords(db, 'tasks', lastSyncTime, _mapTask);
    payload['sessions'] = await _getSyncTableRecords(db, 'sessions', lastSyncTime, _mapSession);
    payload['task_recurrence_completions'] = await _getSyncTableRecords(db, 'task_recurrence_completions', lastSyncTime, _mapRecurrenceCompletion);
    
    // settings 特殊处理：排除同步配置相关的 key
    final SYNC_KEYS = ['syncServerUrl', 'syncToken', 'syncUserId', 'lastSyncTime', 'syncDir'];
    final settingsRecords = await db.query('settings', 
        where: 'updated_at > ? AND key NOT IN (${SYNC_KEYS.map((_) => '?').join(',')})',
        whereArgs: [lastSyncTime, ...SYNC_KEYS]);
    
    payload['settings'] = settingsRecords.map((r) => {
      'id': r['key'],
      'updatedAt': r['updated_at'],
      'data': {
        'key': r['key'],
        'value': r['value'],
      }
    }).toList();

    return payload;
  }

  static Future<List<Map<String, dynamic>>> _getSyncTableRecords(
      Database db, String table, int lastSyncTime, Map<String, dynamic> Function(Map<String, dynamic>) mapper) async {
    // 必须同时查询软删除记录（deleted = 1），否则删除操作无法跨设备同步
    final records = await db.query(table, where: 'updated_at > ? OR deleted = 1', whereArgs: [lastSyncTime]);
    return records.map((r) {
      final mapped = mapper(r);
      return {
        'id': r['id'],
        'updatedAt': r['updated_at'],
        'deleted': (r['deleted'] as int) == 1,
        'data': mapped,
      };
    }).toList();
  }

  /// 应用从服务器下载的同步变更
  static Future<void> applySyncChanges(Map<String, dynamic> tables) async {
    final db = await database;
    await db.transaction((txn) async {
      if (tables['lists'] != null) await _applyTableChanges(txn, 'lists', tables['lists'], _unmapList);
      if (tables['tasks'] != null) await _applyTableChanges(txn, 'tasks', tables['tasks'], _unmapTask);
      if (tables['sessions'] != null) await _applyTableChanges(txn, 'sessions', tables['sessions'], _unmapSession);
      if (tables['task_recurrence_completions'] != null) {
        await _applyTableChanges(txn, 'task_recurrence_completions', tables['task_recurrence_completions'], _unmapRecurrenceCompletion);
      }
      if (tables['settings'] != null) await _applySettingsChanges(txn, tables['settings']);
    });
  }

  static Future<void> _applyTableChanges(Transaction txn, String table, dynamic records, Map<String, dynamic> Function(Map<String, dynamic>) unmapper) async {
    if (records is! List) return;
    for (final item in records) {
      final id = item['id'] as String;
      if (item['deleted'] == true) {
        // 服务器端已删除，本地硬删除
        await txn.delete(table, where: 'id = ?', whereArgs: [id]);
      } else {
        // 服务器端未删除：检查本地是否已有更新的删除记录，防止复活
        final localRows = await txn.query(table,
            where: 'id = ? AND deleted = 1', whereArgs: [id],
            columns: ['updated_at']);
        if (localRows.isNotEmpty) {
          final localUpdatedAt = localRows.first['updated_at'] as int;
          final serverUpdatedAt = item['updatedAt'] as int? ?? 0;
          // 本地删除时间 ≥ 服务器版本时间 → 保留本地删除，不复活
          if (localUpdatedAt >= serverUpdatedAt) {
            continue;
          }
          // 服务器版本更新 → 服务器胜出，允许复活（可能是在其他设备上撤销了删除）
        }

        final data = item['data'] as Map<String, dynamic>;
        final row = unmapper(data);
        row['updated_at'] = item['updatedAt'];
        row['deleted'] = 0;
        await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static Future<void> _applySettingsChanges(Transaction txn, dynamic records) async {
    if (records is! List) return;
    for (final item in records) {
      final data = item['data'] as Map<String, dynamic>;
      final key = data['key'] as String;
      final value = data['value'] as String;
      await txn.insert('settings', {
        'key': key,
        'value': value,
        'updated_at': item['updatedAt'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ========== 逆映射方法 (用于同步写入) ==========

  static Map<String, dynamic> _unmapList(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'name': data['name'],
      'is_system': (data['isSystem'] ?? false) ? 1 : 0,
      'sort_order': data['sortOrder'] ?? 0,
      'created_at': data['createdAt'],
      // updated_at 由调用方在 _applyTableChanges 中统一设置
    };
  }

  static Map<String, dynamic> _unmapTask(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'list_id': data['listId'],
      'title': data['title'],
      'notes': data['notes'],
      'completed': (data['completed'] ?? false) ? 1 : 0,
      'completed_at': data['completedAt'],
      'due_date': data['dueDate'],
      'due_time': data['dueTime'],
      'sort_order': data['sortOrder'] ?? 0,
      'is_my_day': (data['isMyDay'] ?? false) ? 1 : 0,
      'my_day_added_at': data['myDayAddedAt'],
      'recurrence_config': data['recurrenceConfig'] != null ? _encodeJson(data['recurrenceConfig']) : null,
      'expected_minutes': data['expectedMinutes'],
      'is_important': (data['isImportant'] ?? false) ? 1 : 0,
      'reminder_at': data['reminderAt'],
      'calendar_event_id': data['calendarEventId'],
      'created_at': data['createdAt'],
    };
  }

  static Map<String, dynamic> _unmapSession(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'task_id': data['taskId'],
      'task_title': data['taskTitle'],
      'timer_mode': data['timerMode'],
      'duration_seconds': data['durationSeconds'],
      'planned_duration_seconds': data['plannedDurationSeconds'],
      'completed': (data['completed'] ?? false) ? 1 : 0,
      'started_at': data['startedAt'],
      'completed_at': data['completedAt'],
    };
  }

  static Map<String, dynamic> _unmapRecurrenceCompletion(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'task_id': data['taskId'],
      'completion_date': data['completionDate'],
      'completed_at': data['completedAt'],
      'created_at': data['createdAt'],
    };
  }

  static Future<Map<String, dynamic>> getDebugInfo() async {
    final db = await database;
    final listsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM lists')) ?? 0;
    final tasksCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tasks')) ?? 0;
    final sessionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sessions')) ?? 0;
    final dbPath = await getDatabasesPath();
    return {
      'dbOpen': true,
      'lists': listsCount,
      'tasks': tasksCount,
      'sessions': sessionsCount,
      'dbPath': '$dbPath/focus_my_time.db',
    };
  }

  static Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return '$dbPath/focus_my_time.db';
  }

  static Future<Map<String, dynamic>> runDownloadTest() async {
    // Simulated test download - in production this would actually test the sync
    final lists = await getLists();
    final tasks = await getAllTasks();
    return {
      'listsCount': lists.length,
      'tasksCount': tasks.length,
    };
  }

  // ========== AI 对话 ==========

  static Future<Map<String, dynamic>> createAiConversation({String? title}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'conv-${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('ai_conversations', {
      'id': id,
      'title': title,
      'created_at': now,
      'updated_at': now,
    });
    return {'id': id, 'title': title, 'createdAt': now, 'updatedAt': now};
  }

  static Future<void> updateAiConversationTitle(String id, String title) async {
    final db = await database;
    await db.update('ai_conversations', {
      'title': title,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Map<String, dynamic>>> getAiConversations() async {
    final db = await database;
    final result = await db.query('ai_conversations',
        where: 'deleted = 0', orderBy: 'updated_at DESC');
    return result.map((r) => {
      'id': r['id'],
      'title': r['title'],
      'createdAt': r['created_at'],
      'updatedAt': r['updated_at'],
    }).toList();
  }

  static Future<void> deleteAiConversation(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('ai_messages', {'deleted': 1, 'updated_at': now},
        where: 'conversation_id = ?', whereArgs: [id]);
    await db.update('ai_operations', {'deleted': 1, 'updated_at': now},
        where: 'message_id IN (SELECT id FROM ai_messages WHERE conversation_id = ?)', whereArgs: [id]);
    await db.update('ai_conversations', {'deleted': 1, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
  }

  // ========== AI 消息 ==========

  static Future<Map<String, dynamic>> insertAiMessage({
    required String conversationId,
    required String role,
    required String content,
    String? toolCallsJson,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'msg-${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('ai_messages', {
      'id': id,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'tool_calls_json': toolCallsJson,
      'created_at': now,
      'updated_at': now,
    });
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'toolCallsJson': toolCallsJson,
      'createdAt': now,
    };
  }

  static Future<List<Map<String, dynamic>>> getAiMessages(String conversationId) async {
    final db = await database;
    final result = await db.query('ai_messages',
        where: 'conversation_id = ? AND deleted = 0',
        whereArgs: [conversationId],
        orderBy: 'created_at');
    return result.map((r) => {
      'id': r['id'],
      'conversationId': r['conversation_id'],
      'role': r['role'],
      'content': r['content'],
      'toolCallsJson': r['tool_calls_json'],
      'createdAt': r['created_at'],
    }).toList();
  }

  // ========== AI 操作 ==========

  static Future<Map<String, dynamic>> insertAiOperation({
    required String messageId,
    required String type,
    required String paramsJson,
    required String summary,
    String? reasoning,
    String status = 'pending',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'aio-${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('ai_operations', {
      'id': id,
      'message_id': messageId,
      'type': type,
      'params_json': paramsJson,
      'summary': summary,
      'reasoning': reasoning,
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
    return {
      'id': id,
      'messageId': messageId,
      'type': type,
      'paramsJson': paramsJson,
      'summary': summary,
      'reasoning': reasoning,
      'status': status,
      'createdAt': now,
    };
  }

  static Future<List<Map<String, dynamic>>> getAiOperations(String messageId) async {
    final db = await database;
    final result = await db.query('ai_operations',
        where: 'message_id = ? AND deleted = 0',
        whereArgs: [messageId],
        orderBy: 'created_at');
    return result.map((r) => {
      'id': r['id'],
      'messageId': r['message_id'],
      'type': r['type'],
      'paramsJson': r['params_json'],
      'summary': r['summary'],
      'reasoning': r['reasoning'],
      'status': r['status'],
      'errorMessage': r['error_message'],
      'createdAt': r['created_at'],
    }).toList();
  }

  static Future<void> updateAiOperationStatus(String id, String status, {String? errorMessage}) async {
    final db = await database;
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (errorMessage != null) {
      updates['error_message'] = errorMessage;
    }
    await db.update('ai_operations', updates, where: 'id = ?', whereArgs: [id]);
  }

  static String _encodeJson(Map<String, dynamic> json) {
    return jsonEncode(json);
  }

  static Map<String, dynamic> _decodeJson(String encoded) {
    try {
      return jsonDecode(encoded) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }
}
