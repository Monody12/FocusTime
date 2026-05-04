import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'focus_timer.db');

    return await openDatabase(
      path,
      version: 1,
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
        updated_at INTEGER NOT NULL
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
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
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
        updated_at INTEGER NOT NULL
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
        UNIQUE(task_id, completion_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

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
      'id': 'system-all-tasks',
      'name': '任务',
      'is_system': 1,
      'sort_order': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来迁移时使用
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
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========== 清单 ==========

  static Future<List<Map<String, dynamic>>> getLists() async {
    final db = await database;
    return await db.query('lists', orderBy: 'sort_order');
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

  static Future<void> deleteList(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'list_id = ?', whereArgs: [id]);
    await db.delete('lists', where: 'id = ?', whereArgs: [id]);
  }

  // ========== 任务 ==========

  static Future<List<Map<String, dynamic>>> getTasksByList(String listId) async {
    final db = await database;
    final result = await db.query('tasks',
        where: 'list_id = ?', whereArgs: [listId], orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getMyDayTasks() async {
    final db = await database;
    final result = await db.query('tasks',
        where: 'is_my_day = 1', orderBy: 'sort_order');
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    final result = await db.query('tasks', orderBy: 'sort_order');
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

    mapped['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    mapped['id'] = id;

    final sets = mapped.keys.where((k) => k != 'id').map((k) => '$k = ?').join(', ');
    final values = mapped.keys.where((k) => k != 'id').map((k) => mapped[k]).toList();

    await db.rawUpdate('UPDATE tasks SET $sets WHERE id = ?', [...values, id]);
  }

  static Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('sessions', where: 'task_id = ?', whereArgs: [id]);
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> toggleTaskComplete(String id) async {
    final db = await database;
    final result = await db.query('tasks', columns: ['completed'], where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return;

    final currentCompleted = result.first['completed'] as int;
    final newCompleted = currentCompleted == 1 ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update('tasks', {
      'completed': newCompleted,
      'completed_at': newCompleted == 1 ? now : null,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> addToMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('tasks', {
      'is_my_day': 1,
      'my_day_added_at': now,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [taskId]);
  }

  static Future<void> removeFromMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('tasks', {
      'is_my_day': 0,
      'my_day_added_at': null,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [taskId]);
  }

  static Future<void> reorderTasks(List<String> taskIds) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < taskIds.length; i++) {
      await db.update('tasks', {'sort_order': i, 'updated_at': now},
          where: 'id = ?', whereArgs: [taskIds[i]]);
    }
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
        where: 'started_at BETWEEN ? AND ?', whereArgs: [start, end]);
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByDateRange(
      String startDate, String endDate) async {
    final db = await database;
    final start = DateTime.parse('$startDate 00:00:00').millisecondsSinceEpoch;
    final end = DateTime.parse('$endDate 23:59:59').millisecondsSinceEpoch;
    final result = await db.query('sessions',
        where: 'started_at BETWEEN ? AND ?', whereArgs: [start, end], orderBy: 'started_at');
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByTaskId(String taskId) async {
    final db = await database;
    final result = await db.query('sessions',
        where: 'task_id = ?', whereArgs: [taskId], orderBy: 'started_at DESC');
    return result.map(_mapSession).toList();
  }

  // ========== 重复完成记录 ==========

  static Future<bool> toggleRecurrenceCompletion(String taskId, String date) async {
    final db = await database;
    final existing = await db.query('task_recurrence_completions',
        where: 'task_id = ? AND completion_date = ?', whereArgs: [taskId, date]);

    if (existing.isNotEmpty) {
      await db.delete('task_recurrence_completions',
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
        where: 'task_id = ?', whereArgs: [taskId], orderBy: 'completion_date DESC');
    return result.map(_mapRecurrenceCompletion).toList();
  }

  static Future<List<Map<String, dynamic>>> getRecurrenceCompletionsByDateRange(
      String taskId, String startDate, String endDate) async {
    final db = await database;
    final result = await db.query('task_recurrence_completions',
        where: 'task_id = ? AND completion_date BETWEEN ? AND ?',
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
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
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
      'dbPath': '$dbPath/focus_timer.db',
    };
  }

  static Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return '$dbPath/focus_timer.db';
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

  static String _encodeJson(Map<String, dynamic> json) {
    return json.entries.map((e) => '${e.key}:${e.value}').join(';');
  }

  static Map<String, dynamic> _decodeJson(String encoded) {
    final map = <String, dynamic>{};
    for (final pair in encoded.split(';')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        final key = parts[0];
        final value = parts[1];
        if (value == 'null') {
          map[key] = null;
        } else if (int.tryParse(value) != null) {
          map[key] = int.parse(value);
        } else if (value == 'true') {
          map[key] = true;
        } else if (value == 'false') {
          map[key] = false;
        } else {
          map[key] = value;
        }
      }
    }
    return map;
  }
}