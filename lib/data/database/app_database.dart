import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:uuid/uuid.dart';
import 'package:focus_my_time/data/database/database_file_operations.dart'
    as file_operations;
import 'package:focus_my_time/data/database/memo_database.dart';

class AppDatabase {
  static Database? _database;
  static const _uuid = Uuid();
  static const _schemaVersion = 14;
  static const Map<String, String> _taskSyncFields = {
    'listId': 'list_id',
    'title': 'title',
    'notes': 'notes',
    'completed': 'completed',
    'completedAt': 'completed_at',
    'dueDate': 'due_date',
    'dueTime': 'due_time',
    'sortOrder': 'sort_order',
    'isMyDay': 'is_my_day',
    'myDayAddedAt': 'my_day_added_at',
    'recurrenceConfig': 'recurrence_config',
    'expectedMinutes': 'expected_minutes',
    'isImportant': 'is_important',
    'reminderAt': 'reminder_at',
    'archived': 'archived',
    'archivedAt': 'archived_at',
  };

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
    if (kIsWeb) {
      throw UnsupportedError('浏览器请使用 JSON 备份');
    }
    final sourcePath = await getDbPath();
    if (!await file_operations.databaseFileExists(sourcePath)) {
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
      await file_operations.ensureDatabaseOutputParent(outputPath);
      await file_operations.copyDatabaseFile(sourcePath, outputPath);
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
    if (kIsWeb) {
      throw UnsupportedError('浏览器请使用 JSON 备份');
    }
    await validateBackupFile(backupPath);

    final dbPath = await getDbPath();
    await close();
    // 删除旧的 WAL/SHM/journal，防止旧的 sidecar 文件干扰新数据库
    await _deleteDatabaseSidecars(dbPath);

    try {
      await file_operations.copyDatabaseFile(backupPath, dbPath);
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
  /// 2. 数据库版本号是否在支持范围内（≤ 当前版本 13）
  /// 3. 必要的数据表是否存在（lists, tasks, sessions, settings）
  static Future<void> validateBackupFile(String backupPath) async {
    if (kIsWeb) {
      throw UnsupportedError('浏览器不支持 SQLite 文件校验');
    }
    if (!await file_operations.databaseFileExists(backupPath)) {
      throw Exception('备份文件不存在');
    }

    Database? backupDb;
    try {
      // 以只读模式打开备份文件进行校验，不修改原始备份
      backupDb = await file_operations.openReadOnlyDatabaseFile(backupPath);
      final version = await backupDb.getVersion();
      if (version > _schemaVersion) {
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
    if (kIsWeb) return;
    for (final path in ['$dbPath-wal', '$dbPath-shm', '$dbPath-journal']) {
      await file_operations.deleteDatabaseFileIfExists(path);
    }
  }

  static Future<Database> _initDatabase() async {
    final path = kIsWeb
        ? 'focus_my_time.db'
        : join(await getDatabasesPath(), 'focus_my_time.db');

    return await openDatabase(
      path,
      version: _schemaVersion,
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
        icon_key TEXT NOT NULL DEFAULT 'list',
        pinned INTEGER NOT NULL DEFAULT 0,
        top_order INTEGER,
        hidden INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
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
        archived INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
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

    await _createSyncFieldVersionsTable(db);

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

    await _createMemoTables(db);

    // 加速提醒查询的复合索引
    await db.execute(
      'CREATE INDEX idx_tasks_reminders ON tasks(deleted, completed, reminder_at)',
    );

    // 种子数据
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('lists', {
      'id': 'system-my-day',
      'name': '我的一天',
      'is_system': 1,
      'sort_order': 0,
      'icon_key': 'myDay',
      'pinned': 1,
      'top_order': 0,
      'hidden': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('lists', {
      'id': 'system-important',
      'name': '重要',
      'is_system': 1,
      'sort_order': 1,
      'icon_key': 'important',
      'pinned': 1,
      'top_order': 1,
      'hidden': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('lists', {
      'id': 'system-all-tasks',
      'name': '任务',
      'is_system': 1,
      'sort_order': 2,
      'icon_key': 'tasks',
      'pinned': 1,
      'top_order': 2,
      'hidden': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Memo data is kept in separate tables so the editor, attachment manager,
  /// and sync layer can evolve without coupling to task records.  All tables
  /// carry updated/deleted fields because memo content must sync offline and
  /// deletions must remain as tombstones until every device has seen them.
  static Future<void> _createMemoTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_folders (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memo_folders_parent ON memo_folders(parent_id, deleted, sort_order)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memos (
        id TEXT PRIMARY KEY,
        folder_id TEXT,
        title TEXT,
        body_md TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        encrypt_title INTEGER NOT NULL DEFAULT 0,
        encrypted_payload TEXT,
        crypto_version INTEGER NOT NULL DEFAULT 1,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        archived_at INTEGER,
        ai_allowed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memos_list ON memos(folder_id, deleted, archived, pinned, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memos_updated ON memos(deleted, updated_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_tag_links (
        id TEXT PRIMARY KEY,
        memo_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(memo_id, tag_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memo_tag_links_memo ON memo_tag_links(memo_id, deleted)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_versions (
        id TEXT PRIMARY KEY,
        memo_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        title TEXT,
        body_md TEXT,
        encrypted_payload TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(memo_id, version_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memo_versions_memo ON memo_versions(memo_id, deleted, version_number DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_attachments (
        id TEXT PRIMARY KEY,
        memo_id TEXT,
        version_id TEXT,
        filename TEXT,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        storage_key TEXT,
        sha256 TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        encrypted_payload TEXT,
        upload_status TEXT NOT NULL DEFAULT 'pending',
        width INTEGER,
        height INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memo_attachments_memo ON memo_attachments(memo_id, version_id, deleted)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memo_attachments_updated ON memo_attachments(deleted, updated_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS memo_shares (
        id TEXT PRIMARY KEY,
        attachment_id TEXT NOT NULL,
        share_kind TEXT NOT NULL,
        token_hash TEXT NOT NULL,
        expires_at INTEGER,
        password_hash TEXT,
        public_storage_key TEXT,
        revoked INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS privacy_vault (
        id TEXT PRIMARY KEY,
        kdf_name TEXT NOT NULL,
        kdf_params TEXT NOT NULL,
        salt TEXT NOT NULL,
        wrapped_master_key TEXT NOT NULL,
        wrap_nonce TEXT NOT NULL,
        recovery_wrapped_master_key TEXT NOT NULL,
        recovery_nonce TEXT NOT NULL,
        crypto_version INTEGER NOT NULL DEFAULT 1,
        config_revision INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // 增加删除标记位以支持同步
      await db.execute(
        'ALTER TABLE lists ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE tasks ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE task_recurrence_completions ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 3) {
      // 为设置表增加时间戳以支持同步
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        // Ignore if column already exists
      }
    }

    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN is_important INTEGER NOT NULL DEFAULT 0',
        );
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
      await db.execute(
        "UPDATE lists SET sort_order = sort_order + 1 WHERE id = 'system-all-tasks'",
      );
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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_reminders ON tasks(deleted, completed, reminder_at)',
      );
    }

    if (oldVersion < 10) {
      await db.execute(
        'ALTER TABLE lists ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE lists ADD COLUMN archived_at INTEGER');
      await db.execute(
        'ALTER TABLE tasks ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE tasks ADD COLUMN archived_at INTEGER');
    }

    if (oldVersion < 11) {
      await _createSyncFieldVersionsTable(db);
      await _backfillTaskFieldVersions(db);
    }

    if (oldVersion < 12) {
      await _addListCustomizationColumns(db);
    }

    if (oldVersion < 13) {
      await _repairMisappliedListArchives(db);
    }

    if (oldVersion < 14) {
      await _createMemoTables(db);
    }
  }

  static Future<void> _addListCustomizationColumns(DatabaseExecutor db) async {
    final migrations = [
      "ALTER TABLE lists ADD COLUMN icon_key TEXT NOT NULL DEFAULT 'list'",
      'ALTER TABLE lists ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE lists ADD COLUMN top_order INTEGER',
      'ALTER TABLE lists ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0',
    ];
    for (final sql in migrations) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already exists in partially migrated databases.
      }
    }

    await db.update('lists', {
      'icon_key': 'myDay',
      'pinned': 1,
      'top_order': 0,
      'hidden': 0,
    }, where: "id = 'system-my-day'");
    await db.update('lists', {
      'icon_key': 'important',
      'pinned': 1,
      'top_order': 1,
      'hidden': 0,
    }, where: "id = 'system-important'");
    await db.update('lists', {
      'icon_key': 'tasks',
      'pinned': 1,
      'top_order': 2,
      'hidden': 0,
    }, where: "id = 'system-all-tasks'");
  }

  static Future<void> _createSyncFieldVersionsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_field_versions (
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (table_name, record_id, field_name)
      )
    ''');
  }

  static Future<void> _backfillTaskFieldVersions(DatabaseExecutor db) async {
    final rows = await db.query('tasks', columns: ['id', 'updated_at']);
    for (final row in rows) {
      await _setFieldVersions(
        db,
        'tasks',
        row['id'] as String,
        _taskSyncFields.keys,
        row['updated_at'] as int? ?? 0,
      );
    }
  }

  // ========== 设置 ==========

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _setFieldVersions(
    DatabaseExecutor db,
    String tableName,
    String recordId,
    Iterable<String> fieldNames,
    int updatedAt,
  ) async {
    final uniqueFields = fieldNames.toSet();
    if (uniqueFields.isEmpty) return;

    for (final fieldName in uniqueFields) {
      await db.insert('sync_field_versions', {
        'table_name': tableName,
        'record_id': recordId,
        'field_name': fieldName,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<Map<String, int>> _getFieldVersions(
    DatabaseExecutor db,
    String tableName,
    String recordId,
  ) async {
    final rows = await db.query(
      'sync_field_versions',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: [tableName, recordId],
    );
    return {
      for (final row in rows)
        row['field_name'] as String: row['updated_at'] as int,
    };
  }

  static Map<String, int> _taskFieldVersionsFromData(
    Map<String, dynamic> data,
    int fallbackUpdatedAt,
  ) {
    final rawVersions = data['_fieldUpdatedAt'];
    if (rawVersions is Map) {
      final versions = <String, int>{};
      for (final entry in rawVersions.entries) {
        final fieldName = entry.key.toString();
        if (!_taskSyncFields.containsKey(fieldName)) continue;
        final value = entry.value;
        final parsed = value is int ? value : int.tryParse(value.toString());
        versions[fieldName] = parsed ?? fallbackUpdatedAt;
      }
      for (final fieldName in _taskSyncFields.keys) {
        versions.putIfAbsent(fieldName, () => fallbackUpdatedAt);
      }
      return versions;
    }

    return {
      for (final fieldName in _taskSyncFields.keys)
        fieldName: fallbackUpdatedAt,
    };
  }

  static int _maxTimestamp(int a, int b) => a > b ? a : b;

  static Future<List<String>> _getActiveTaskIdsForList(
    DatabaseExecutor db,
    String listId,
  ) async {
    final rows = await db.query(
      'tasks',
      columns: ['id'],
      where: 'list_id = ? AND deleted = 0',
      whereArgs: [listId],
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  static Future<void> _setTaskFieldVersionsForIds(
    DatabaseExecutor db,
    Iterable<String> taskIds,
    Iterable<String> fieldNames,
    int updatedAt,
  ) async {
    for (final taskId in taskIds) {
      await _setFieldVersions(db, 'tasks', taskId, fieldNames, updatedAt);
    }
  }

  static Future<void> _softDeleteSessionsForTaskIds(
    DatabaseExecutor db,
    Iterable<String> taskIds,
    int updatedAt,
  ) async {
    final ids = taskIds.toList();
    if (ids.isEmpty) return;
    await db.update(
      'sessions',
      {'deleted': 1, 'updated_at': updatedAt},
      where:
          'task_id IN (${List.filled(ids.length, '?').join(',')}) AND deleted = 0',
      whereArgs: ids,
    );
  }

  static Future<void> _cascadeListDeleted(
    DatabaseExecutor db,
    String listId,
    int updatedAt,
  ) async {
    final taskIds = await _getActiveTaskIdsForList(db, listId);
    if (taskIds.isEmpty) return;
    await _softDeleteSessionsForTaskIds(db, taskIds, updatedAt);
    await db.rawUpdate(
      '''
      UPDATE tasks
      SET deleted = 1,
          updated_at = CASE WHEN updated_at > ? THEN updated_at ELSE ? END
      WHERE list_id = ? AND deleted = 0
      ''',
      [updatedAt, updatedAt, listId],
    );
    await _setTaskFieldVersionsForIds(
      db,
      taskIds,
      _taskSyncFields.keys,
      updatedAt,
    );
  }

  static Future<void> _cascadeListArchived(
    DatabaseExecutor db,
    String listId, {
    required bool archived,
    required int updatedAt,
    int? archivedAt,
  }) async {
    final taskRows = await db.query(
      'tasks',
      columns: ['id', 'updated_at'],
      where: 'list_id = ? AND deleted = 0',
      whereArgs: [listId],
    );
    final taskIds = <String>[];
    for (final row in taskRows) {
      final taskId = row['id'] as String;
      final fallbackUpdatedAt = row['updated_at'] as int? ?? 0;
      final versions = await _getFieldVersions(db, 'tasks', taskId);
      final archivedVersion = versions['archived'] ?? fallbackUpdatedAt;
      final archivedAtVersion = versions['archivedAt'] ?? fallbackUpdatedAt;
      if (archivedVersion <= updatedAt && archivedAtVersion <= updatedAt) {
        taskIds.add(taskId);
      }
    }
    if (taskIds.isEmpty) return;
    await db.rawUpdate(
      '''
      UPDATE tasks
      SET archived = ?,
          archived_at = ?,
          updated_at = CASE WHEN updated_at > ? THEN updated_at ELSE ? END
      WHERE id IN (${List.filled(taskIds.length, '?').join(',')}) AND deleted = 0
      ''',
      [
        archived ? 1 : 0,
        archived ? archivedAt : null,
        updatedAt,
        updatedAt,
        ...taskIds,
      ],
    );
    await _setTaskFieldVersionsForIds(db, taskIds, [
      'archived',
      'archivedAt',
    ], updatedAt);
  }

  /// 修复旧版同步顺序造成的错误归档：任务已经移动到活动清单，但仍继承
  /// 另一已归档清单的归档状态和字段时间戳。
  static Future<int> _repairMisappliedListArchives(DatabaseExecutor db) async {
    final activeListRows = await db.query(
      'lists',
      columns: ['id'],
      where: 'deleted = 0 AND archived = 0',
    );
    final activeListIds = activeListRows
        .map((row) => row['id'] as String)
        .toSet();
    if (activeListIds.isEmpty) return 0;

    final archivedListRows = await db.query(
      'lists',
      columns: ['archived_at'],
      where: 'archived = 1 AND archived_at IS NOT NULL',
    );
    final archivedListTimes = archivedListRows
        .map((row) => row['archived_at'] as int?)
        .whereType<int>()
        .toSet();
    if (archivedListTimes.isEmpty) return 0;

    final taskRows = await db.query(
      'tasks',
      columns: ['id', 'list_id', 'updated_at', 'archived_at'],
      where: 'deleted = 0 AND archived = 1 AND archived_at IS NOT NULL',
    );
    var repaired = 0;
    for (final row in taskRows) {
      final listId = row['list_id'] as String;
      final archivedAt = row['archived_at'] as int?;
      if (!activeListIds.contains(listId) ||
          archivedAt == null ||
          !archivedListTimes.contains(archivedAt)) {
        continue;
      }

      final taskId = row['id'] as String;
      final taskUpdatedAt = row['updated_at'] as int? ?? 0;
      final versions = await _getFieldVersions(db, 'tasks', taskId);
      final listIdVersion = versions['listId'] ?? taskUpdatedAt;
      final archivedVersion = versions['archived'] ?? taskUpdatedAt;
      final archivedAtVersion = versions['archivedAt'] ?? taskUpdatedAt;
      if (listIdVersion >= archivedVersion ||
          archivedAtVersion != archivedVersion ||
          archivedAt != archivedVersion) {
        continue;
      }

      var repairUpdatedAt = DateTime.now().millisecondsSinceEpoch + 1;
      for (final timestamp in [
        taskUpdatedAt,
        listIdVersion,
        archivedVersion,
        archivedAtVersion,
      ]) {
        if (repairUpdatedAt <= timestamp) repairUpdatedAt = timestamp + 1;
      }
      await db.update(
        'tasks',
        {'archived': 0, 'archived_at': null, 'updated_at': repairUpdatedAt},
        where: 'id = ? AND deleted = 0',
        whereArgs: [taskId],
      );
      await _setFieldVersions(db, 'tasks', taskId, const [
        'archived',
        'archivedAt',
      ], repairUpdatedAt);
      repaired++;
    }
    return repaired;
  }

  // ========== 清单 ==========

  static Future<List<Map<String, dynamic>>> getLists() async {
    final db = await database;
    final result = await db.query(
      'lists',
      where: 'deleted = 0 AND archived = 0',
      orderBy: 'sort_order',
    );
    return result.map(_mapList).toList();
  }

  static Future<List<Map<String, dynamic>>> getArchivedLists() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT l.*,
        (
          SELECT COUNT(*)
          FROM tasks t
          WHERE t.list_id = l.id AND t.deleted = 0 AND t.archived = 1
        ) AS task_count
      FROM lists l
      WHERE l.deleted = 0 AND l.archived = 1
      ORDER BY l.archived_at DESC, l.updated_at DESC
    ''');
    return result.map((row) {
      final mapped = _mapList(row);
      mapped['taskCount'] = row['task_count'] ?? 0;
      return mapped;
    }).toList();
  }

  /// 将数据库行映射为应用程序使用的 TaskList 对象，并处理命名格式转换（snake_case -> camelCase）
  static Map<String, dynamic> _mapList(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'name': row['name'],
      // 数据库存储为 0/1，这里转换为布尔值
      'isSystem': (row['is_system'] as int) == 1,
      'sortOrder': row['sort_order'],
      'iconKey': row['icon_key'] as String? ?? 'list',
      'pinned': (row['pinned'] as int? ?? 0) == 1,
      'topOrder': row['top_order'],
      'hidden': (row['hidden'] as int? ?? 0) == 1,
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'archived': (row['archived'] as int? ?? 0) == 1,
      'archivedAt': row['archived_at'],
      'deleted': (row['deleted'] as int) == 1,
    };
  }

  static Future<Map<String, dynamic>> createList(String name) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM lists WHERE deleted = 0 AND archived = 0',
          ),
        ) ??
        0;
    final id = 'list-${_uuid.v4()}';

    await db.insert('lists', {
      'id': id,
      'name': name,
      'is_system': 0,
      'sort_order': count,
      'icon_key': 'list',
      'pinned': 0,
      'top_order': null,
      'hidden': 0,
      'created_at': now,
      'updated_at': now,
    });

    return {
      'id': id,
      'name': name,
      'isSystem': false,
      'sortOrder': count,
      'iconKey': 'list',
      'pinned': false,
      'topOrder': null,
      'hidden': false,
      'createdAt': now,
      'updatedAt': now,
      'archived': false,
      'archivedAt': null,
    };
  }

  static Future<void> updateList(String id, String name) async {
    final db = await database;
    await db.update(
      'lists',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [id],
    );
  }

  static Future<void> updateListCustomization(
    String id, {
    String? iconKey,
    bool? pinned,
    int? topOrder,
    bool? hidden,
    bool clearTopOrder = false,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (iconKey != null) updates['icon_key'] = iconKey;
    if (pinned != null) updates['pinned'] = pinned ? 1 : 0;
    if (topOrder != null || clearTopOrder) updates['top_order'] = topOrder;
    if (hidden != null) updates['hidden'] = hidden ? 1 : 0;
    if (updates.isEmpty) return;
    updates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'lists',
      updates,
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [id],
    );
  }

  static Future<void> reorderTopLists(List<String> listIds) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < listIds.length; i++) {
      batch.update(
        'lists',
        {'pinned': 1, 'top_order': i, 'updated_at': now},
        where: 'id = ? AND deleted = 0 AND archived = 0',
        whereArgs: [listIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> resetListIcons() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update('lists', {
        'icon_key': 'list',
        'updated_at': now,
      }, where: 'deleted = 0 AND is_system = 0');
      await txn.update('lists', {
        'icon_key': 'myDay',
        'updated_at': now,
      }, where: "id = 'system-my-day'");
      await txn.update('lists', {
        'icon_key': 'important',
        'updated_at': now,
      }, where: "id = 'system-important'");
      await txn.update('lists', {
        'icon_key': 'tasks',
        'updated_at': now,
      }, where: "id = 'system-all-tasks'");
    });
  }

  static Future<void> resetTopListOrder() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update('lists', {
        'pinned': 1,
        'top_order': 0,
        'hidden': 0,
        'updated_at': now,
      }, where: "id = 'system-my-day'");
      await txn.update('lists', {
        'pinned': 1,
        'top_order': 1,
        'hidden': 0,
        'updated_at': now,
      }, where: "id = 'system-important'");
      await txn.update('lists', {
        'pinned': 1,
        'top_order': 2,
        'hidden': 0,
        'updated_at': now,
      }, where: "id = 'system-all-tasks'");
      final pinnedCustomLists = await txn.query(
        'lists',
        columns: ['id'],
        where: 'deleted = 0 AND archived = 0 AND is_system = 0 AND pinned = 1',
        orderBy: 'sort_order ASC, created_at ASC',
      );
      for (var i = 0; i < pinnedCustomLists.length; i++) {
        await txn.update(
          'lists',
          {'top_order': i + 3, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [pinnedCustomLists[i]['id']],
        );
      }
    });
  }

  static Future<void> archiveList(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final updatedLists = await txn.update(
        'lists',
        {'archived': 1, 'archived_at': now, 'updated_at': now},
        where: 'id = ? AND deleted = 0 AND is_system = 0 AND pinned = 0',
        whereArgs: [id],
      );
      if (updatedLists == 0) return;
      await _cascadeListArchived(
        txn,
        id,
        archived: true,
        archivedAt: now,
        updatedAt: now,
      );
    });
  }

  static Future<void> restoreList(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final updatedLists = await txn.update(
        'lists',
        {'archived': 0, 'archived_at': null, 'updated_at': now},
        where: 'id = ? AND deleted = 0',
        whereArgs: [id],
      );
      if (updatedLists == 0) return;
      await _cascadeListArchived(txn, id, archived: false, updatedAt: now);
    });
  }

  /// 软删除清单及其下的所有任务
  static Future<void> deleteList(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final updatedLists = await txn.update(
        'lists',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ? AND is_system = 0 AND pinned = 0',
        whereArgs: [id],
      );
      if (updatedLists == 0) return;
      await _cascadeListDeleted(txn, id, now);
    });
  }

  // ========== 任务 ==========

  static Future<Map<String, dynamic>?> getTaskById(
    String id, {
    bool includeArchived = false,
  }) async {
    final db = await database;
    // 过滤已删除任务，防止调用方操作已被软删除的僵尸任务
    final archivedFilter = includeArchived ? '' : 'AND t.archived = 0';
    final result = await db.rawQuery(
      '''
      SELECT t.*, l.name AS list_name
      FROM tasks t
      LEFT JOIN lists l ON l.id = t.list_id AND l.deleted = 0
      WHERE t.id = ? AND t.deleted = 0 $archivedFilter
      LIMIT 1
    ''',
      [id],
    );
    if (result.isEmpty) return null;
    final task = _mapTask(result.first);
    task['listName'] = result.first['list_name'];
    return task;
  }

  /// Returns every non-deleted task that can contribute to a calendar range.
  /// Archived tasks stay visible as historical records.
  static Future<List<Map<String, dynamic>>> getCalendarTasksByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final start = AppTime.startOfDateMilliseconds(startDate);
    final end = AppTime.endOfDateMilliseconds(endDate);
    final result = await db.rawQuery(
      '''
      SELECT t.*, l.name AS list_name
      FROM tasks t
      LEFT JOIN lists l ON l.id = t.list_id AND l.deleted = 0
      WHERE t.deleted = 0
        AND (
          t.created_at BETWEEN ? AND ?
          OR t.completed_at BETWEEN ? AND ?
          OR t.due_date BETWEEN ? AND ?
          OR (
            t.recurrence_config IS NOT NULL
            AND t.due_date IS NOT NULL
            AND t.due_date <= ?
          )
        )
      ORDER BY COALESCE(t.completed_at, t.created_at) DESC
    ''',
      [start, end, start, end, startDate, endDate, endDate],
    );
    return result.map((row) {
      final task = _mapTask(row);
      task['listName'] = row['list_name'];
      return task;
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getTasksByList(
    String listId,
  ) async {
    final db = await database;
    final result = await db.query(
      'tasks',
      where: 'list_id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [listId],
      orderBy: 'sort_order',
    );
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getMyDayTasks() async {
    final db = await database;
    final result = await db.query(
      'tasks',
      where: 'is_my_day = 1 AND deleted = 0 AND archived = 0',
      orderBy: 'sort_order',
    );
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getImportantTasks() async {
    final db = await database;
    final result = await db.query(
      'tasks',
      where: 'is_important = 1 AND deleted = 0 AND archived = 0',
      orderBy: 'sort_order',
    );
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    final result = await db.query(
      'tasks',
      where: 'deleted = 0 AND archived = 0',
      orderBy: 'sort_order',
    );
    return result.map(_mapTask).toList();
  }

  static Future<List<Map<String, dynamic>>> getArchivedTasks({
    bool excludeTasksInArchivedLists = true,
  }) async {
    final db = await database;
    final listFilter = excludeTasksInArchivedLists
        ? 'AND (l.id IS NULL OR l.deleted = 1 OR l.archived = 0)'
        : '';
    final result = await db.rawQuery('''
      SELECT t.*, l.name AS list_name
      FROM tasks t
      LEFT JOIN lists l ON l.id = t.list_id
      WHERE t.deleted = 0 AND t.archived = 1
      $listFilter
      ORDER BY t.archived_at DESC, t.updated_at DESC
    ''');
    return result.map((row) {
      final mapped = _mapTask(row);
      mapped['listName'] = row['list_name'];
      return mapped;
    }).toList();
  }

  /// 获取所有有待处理提醒的未完成任务（仅返回未来的提醒）
  static Future<List<Map<String, dynamic>>> getActiveReminders() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await db.query(
      'tasks',
      where:
          'deleted = 0 AND archived = 0 AND completed = 0 AND reminder_at IS NOT NULL AND reminder_at > ?',
      whereArgs: [now],
      orderBy: 'reminder_at',
    );
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
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE list_id = ? AND deleted = 0 AND archived = 0',
            [listId],
          ),
        ) ??
        0;
    final id = 'task-${_uuid.v4()}';

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
    await _setFieldVersions(db, 'tasks', id, _taskSyncFields.keys, now);

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
      'archived': false,
      'archivedAt': null,
    };
  }

  static Future<Map<String, dynamic>> duplicateTaskForRecurrence(
    Map<String, dynamic> oldTask,
    String? newDueDate,
    int? newReminderAt,
  ) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'task-${_uuid.v4()}';

    // The oldTask is already mapped (camelCase keys), but we need snake_case for DB insertion.
    final dbInsertMap = {
      'id': id,
      'list_id': oldTask['listId'],
      'title': oldTask['title'],
      'notes': oldTask['notes'],
      'completed': 0,
      'completed_at': null,
      'due_date': newDueDate,
      'due_time': oldTask['dueTime'],
      'sort_order': oldTask['sortOrder'],
      'is_my_day': oldTask['isMyDay'] == true ? 1 : 0,
      'my_day_added_at': oldTask['myDayAddedAt'],
      'recurrence_config': oldTask['recurrenceConfig'] != null
          ? _encodeJson(oldTask['recurrenceConfig'])
          : null,
      'expected_minutes': oldTask['expectedMinutes'],
      'is_important': oldTask['isImportant'] == true ? 1 : 0,
      'reminder_at': newReminderAt,
      'calendar_event_id': null, // Need a new calendar event for the new task
      'created_at': now,
      'updated_at': now,
    };

    await db.insert('tasks', dbInsertMap);
    await _setFieldVersions(db, 'tasks', id, _taskSyncFields.keys, now);

    return {
      'id': id,
      'listId': oldTask['listId'],
      'title': oldTask['title'],
      'notes': oldTask['notes'],
      'completed': false,
      'completedAt': null,
      'dueDate': newDueDate,
      'dueTime': oldTask['dueTime'],
      'sortOrder': oldTask['sortOrder'],
      'isMyDay': oldTask['isMyDay'] == true,
      'myDayAddedAt': oldTask['myDayAddedAt'],
      'recurrenceConfig': oldTask['recurrenceConfig'],
      'expectedMinutes': oldTask['expectedMinutes'],
      'isImportant': oldTask['isImportant'] == true,
      'reminderAt': newReminderAt,
      'calendarEventId': null,
      'createdAt': now,
      'updatedAt': now,
      'archived': false,
      'archivedAt': null,
    };
  }

  /// 原子完成一个重复任务并创建下一次实例。
  ///
  /// 只有当原任务仍处于“未完成且仍带重复配置”状态时才会生成下一次任务，
  /// 用来防止移动端连续点击 checkbox 时重复创建多个下一次任务。
  static Future<Map<String, dynamic>?> completeRecurringTaskAndCreateNext({
    required String id,
    required String newDueDate,
    required int? newReminderAt,
    Map<String, dynamic>? nextRecurrenceConfig,
  }) async {
    final db = await database;
    return db.transaction<Map<String, dynamic>?>((txn) async {
      final rows = await txn.query(
        'tasks',
        where:
            'id = ? AND deleted = 0 AND archived = 0 AND completed = 0 AND recurrence_config IS NOT NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final oldRow = rows.first;
      final now = DateTime.now().millisecondsSinceEpoch;
      final newId = 'task-${_uuid.v4()}';

      final updatedRows = await txn.update(
        'tasks',
        {
          'completed': 1,
          'completed_at': now,
          'recurrence_config': null,
          'updated_at': now,
        },
        where:
            'id = ? AND deleted = 0 AND archived = 0 AND completed = 0 AND recurrence_config IS NOT NULL',
        whereArgs: [id],
      );
      if (updatedRows == 0) return null;

      await _setFieldVersions(txn, 'tasks', id, [
        'completed',
        'completedAt',
        'recurrenceConfig',
      ], now);

      final dbInsertMap = {
        'id': newId,
        'list_id': oldRow['list_id'],
        'title': oldRow['title'],
        'notes': oldRow['notes'],
        'completed': 0,
        'completed_at': null,
        'due_date': newDueDate,
        'due_time': oldRow['due_time'],
        'sort_order': oldRow['sort_order'],
        'is_my_day': oldRow['is_my_day'],
        'my_day_added_at': oldRow['my_day_added_at'],
        'recurrence_config': nextRecurrenceConfig != null
            ? _encodeJson(nextRecurrenceConfig)
            : oldRow['recurrence_config'],
        'expected_minutes': oldRow['expected_minutes'],
        'is_important': oldRow['is_important'],
        'reminder_at': newReminderAt,
        'calendar_event_id': null,
        'created_at': now,
        'updated_at': now,
        'archived': 0,
        'archived_at': null,
        'deleted': 0,
      };

      await txn.insert('tasks', dbInsertMap);
      await _setFieldVersions(txn, 'tasks', newId, _taskSyncFields.keys, now);

      return _mapTask(dbInsertMap);
    });
  }

  static Future<void> updateTask(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final db = await database;
    final mapped = <String, dynamic>{};
    final hasCalendarEventIdUpdate = updates.containsKey('calendarEventId');
    final calendarEventId = updates['calendarEventId'] as String?;

    if (updates.containsKey('title')) mapped['title'] = updates['title'];
    if (updates.containsKey('notes')) mapped['notes'] = updates['notes'];
    if (updates.containsKey('listId')) mapped['list_id'] = updates['listId'];
    if (updates.containsKey('dueDate')) mapped['due_date'] = updates['dueDate'];
    if (updates.containsKey('dueTime')) mapped['due_time'] = updates['dueTime'];
    if (updates.containsKey('sortOrder')) {
      mapped['sort_order'] = updates['sortOrder'];
    }
    if (updates.containsKey('isMyDay')) {
      mapped['is_my_day'] = updates['isMyDay'] ? 1 : 0;
    }
    if (updates.containsKey('myDayAddedAt')) {
      mapped['my_day_added_at'] = updates['myDayAddedAt'];
    }
    if (updates.containsKey('completed')) {
      mapped['completed'] = updates['completed'] ? 1 : 0;
    }
    if (updates.containsKey('completedAt')) {
      mapped['completed_at'] = updates['completedAt'];
    }
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

    if (mapped.isEmpty) {
      if (hasCalendarEventIdUpdate) {
        await updateTaskCalendarEventId(id, calendarEventId);
      }
      return;
    }

    if (hasCalendarEventIdUpdate) {
      mapped['calendar_event_id'] = calendarEventId;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    mapped['updated_at'] = now;
    mapped['id'] = id;

    final sets = mapped.keys
        .where((k) => k != 'id')
        .map((k) => '$k = ?')
        .join(', ');
    final values = mapped.keys
        .where((k) => k != 'id')
        .map((k) => mapped[k])
        .toList();

    // 仅更新未删除的任务，防止操作已被软删除的僵尸记录
    final updatedRows = await db.rawUpdate(
      'UPDATE tasks SET $sets WHERE id = ? AND deleted = 0 AND archived = 0',
      [...values, id],
    );
    if (updatedRows > 0) {
      final changedFields = updates.keys.where(
        (fieldName) => _taskSyncFields.containsKey(fieldName),
      );
      await _setFieldVersions(db, 'tasks', id, changedFields, now);
    }
  }

  /// 仅更新本机系统集成状态，不推进 updated_at，避免触发云同步。
  static Future<void> updateTaskCalendarEventId(
    String id,
    String? calendarEventId,
  ) async {
    final db = await database;
    await db.update(
      'tasks',
      {'calendar_event_id': calendarEventId},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  /// 清空所有本机日历事件引用；这些 ID 不跨设备同步。
  static Future<void> clearTaskCalendarEventIds() async {
    final db = await database;
    await db.update('tasks', {'calendar_event_id': null}, where: 'deleted = 0');
  }

  static Future<void> archiveTask(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedRows = await db.update(
      'tasks',
      {'archived': 1, 'archived_at': now, 'updated_at': now},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (updatedRows > 0) {
      await _setFieldVersions(db, 'tasks', id, ['archived', 'archivedAt'], now);
    }
  }

  static Future<int> autoArchiveCompletedTasks({required int keepCount}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final groups = await db.rawQuery(
      '''
      SELECT list_id, title, COUNT(*) AS count
      FROM tasks
      WHERE deleted = 0 AND archived = 0 AND completed = 1
      GROUP BY list_id, title
      HAVING count > ?
    ''',
      [keepCount],
    );

    var archivedCount = 0;
    for (final group in groups) {
      final rows = await db.rawQuery(
        '''
        SELECT id
        FROM tasks
        WHERE deleted = 0
          AND archived = 0
          AND completed = 1
          AND list_id = ?
          AND title = ?
        ORDER BY completed_at DESC, updated_at DESC
        LIMIT -1 OFFSET ?
      ''',
        [group['list_id'], group['title'], keepCount],
      );
      final ids = rows.map((row) => row['id'] as String).toList();
      if (ids.isEmpty) continue;
      await db.update(
        'tasks',
        {'archived': 1, 'archived_at': now, 'updated_at': now},
        where:
            'id IN (${List.filled(ids.length, '?').join(',')}) AND deleted = 0',
        whereArgs: ids,
      );
      await _setTaskFieldVersionsForIds(db, ids, [
        'archived',
        'archivedAt',
      ], now);
      archivedCount += ids.length;
    }
    return archivedCount;
  }

  static Future<void> restoreTask(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedRows = await db.update(
      'tasks',
      {'archived': 0, 'archived_at': null, 'updated_at': now},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (updatedRows > 0) {
      await _setFieldVersions(db, 'tasks', id, ['archived', 'archivedAt'], now);
    }
  }

  /// 软删除任务及其下的所有会话
  static Future<void> deleteTask(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // 仅更新未删除的会话，防止更新已删除记录的 updated_at 导致重复同步
      await txn.update(
        'sessions',
        {'deleted': 1, 'updated_at': now},
        where: 'task_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      final updatedRows = await txn.update(
        'tasks',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updatedRows > 0) {
        await _setFieldVersions(txn, 'tasks', id, _taskSyncFields.keys, now);
      }
    });
  }

  static Future<void> toggleTaskComplete(String id) async {
    final db = await database;
    // 仅查询未删除的任务，避免对已删除的僵尸任务进行操作
    final result = await db.query(
      'tasks',
      columns: ['completed'],
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [id],
    );
    if (result.isEmpty) return;

    final currentCompleted = result.first['completed'] as int;
    final newCompleted = currentCompleted == 1 ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    final updatedRows = await db.update(
      'tasks',
      {
        'completed': newCompleted,
        'completed_at': newCompleted == 1 ? now : null,
        'updated_at': now,
      },
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [id],
    );
    if (updatedRows > 0) {
      await _setFieldVersions(db, 'tasks', id, [
        'completed',
        'completedAt',
      ], now);
    }
  }

  static Future<void> addToMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的任务
    final updatedRows = await db.update(
      'tasks',
      {'is_my_day': 1, 'my_day_added_at': now, 'updated_at': now},
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [taskId],
    );
    if (updatedRows > 0) {
      await _setFieldVersions(db, 'tasks', taskId, [
        'isMyDay',
        'myDayAddedAt',
      ], now);
    }
  }

  static Future<void> removeFromMyDay(String taskId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅更新未删除的任务
    final updatedRows = await db.update(
      'tasks',
      {'is_my_day': 0, 'my_day_added_at': null, 'updated_at': now},
      where: 'id = ? AND deleted = 0 AND archived = 0',
      whereArgs: [taskId],
    );
    if (updatedRows > 0) {
      await _setFieldVersions(db, 'tasks', taskId, [
        'isMyDay',
        'myDayAddedAt',
      ], now);
    }
  }

  static Future<void> reorderTasks(List<String> taskIds) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < taskIds.length; i++) {
      batch.update(
        'tasks',
        {'sort_order': i, 'updated_at': now},
        where: 'id = ? AND deleted = 0 AND archived = 0',
        whereArgs: [taskIds[i]],
      );
    }
    await batch.commit(noResult: true);
    for (final taskId in taskIds) {
      await _setFieldVersions(db, 'tasks', taskId, ['sortOrder'], now);
    }
  }

  static Future<void> reorderLists(
    List<String> listIds, {
    int offset = 0,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < listIds.length; i++) {
      batch.update(
        'lists',
        {'sort_order': i + offset, 'updated_at': now},
        where: 'id = ? AND deleted = 0 AND archived = 0',
        whereArgs: [listIds[i]],
      );
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
    final id = 'session-${_uuid.v4()}';

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

  static Future<List<Map<String, dynamic>>> getSessionsByDate(
    String date,
  ) async {
    final db = await database;
    final start = AppTime.startOfDateMilliseconds(date);
    final end = AppTime.endOfDateMilliseconds(date);
    final result = await db.query(
      'sessions',
      where: 'started_at BETWEEN ? AND ? AND deleted = 0',
      whereArgs: [start, end],
    );
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final start = AppTime.startOfDateMilliseconds(startDate);
    final end = AppTime.endOfDateMilliseconds(endDate);
    final result = await db.query(
      'sessions',
      where: 'started_at BETWEEN ? AND ? AND deleted = 0',
      whereArgs: [start, end],
      orderBy: 'started_at',
    );
    return result.map(_mapSession).toList();
  }

  static Future<List<Map<String, dynamic>>> getSessionsByTaskId(
    String taskId,
  ) async {
    final db = await database;
    // 过滤已删除的会话，避免在任务详情中显示无效的专注记录
    final result = await db.query(
      'sessions',
      where: 'task_id = ? AND deleted = 0',
      whereArgs: [taskId],
      orderBy: 'started_at DESC',
    );
    return result.map(_mapSession).toList();
  }

  // ========== 重复完成记录 ==========

  static Future<bool> toggleRecurrenceCompletion(
    String taskId,
    String date,
  ) async {
    final db = await database;
    final existing = await db.query(
      'task_recurrence_completions',
      where: 'task_id = ? AND completion_date = ?',
      whereArgs: [taskId, date],
    );

    if (existing.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        'task_recurrence_completions',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return false;
    } else {
      final id = 'rc-${_uuid.v4()}';
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

  static Future<List<Map<String, dynamic>>> getRecurrenceCompletions(
    String taskId,
  ) async {
    final db = await database;
    final result = await db.query(
      'task_recurrence_completions',
      where: 'task_id = ? AND deleted = 0',
      whereArgs: [taskId],
      orderBy: 'completion_date DESC',
    );
    return result.map(_mapRecurrenceCompletion).toList();
  }

  static Future<List<Map<String, dynamic>>> getRecurrenceCompletionsByDateRange(
    String taskId,
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    // 过滤已删除的完成记录
    final result = await db.query(
      'task_recurrence_completions',
      where: 'task_id = ? AND completion_date BETWEEN ? AND ? AND deleted = 0',
      whereArgs: [taskId, startDate, endDate],
      orderBy: 'completion_date DESC',
    );
    return result.map(_mapRecurrenceCompletion).toList();
  }

  static Future<List<Map<String, dynamic>>>
  getAllRecurrenceCompletionsByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final result = await db.query(
      'task_recurrence_completions',
      where: 'completion_date BETWEEN ? AND ? AND deleted = 0',
      whereArgs: [startDate, endDate],
      orderBy: 'completion_date DESC',
    );
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
      'archived': (row['archived'] as int? ?? 0) == 1,
      'archivedAt': row['archived_at'],
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

  static Map<String, dynamic> _mapRecurrenceCompletion(
    Map<String, dynamic> row,
  ) {
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
  static Future<Map<String, List<Map<String, dynamic>>>> getSyncPayload(
    int lastSyncTime, {
    int? memoLastSyncTime,
  }) async {
    final db = await database;
    final payload = <String, List<Map<String, dynamic>>>{};

    // 获取各表的变更记录
    payload['lists'] = await _getSyncTableRecords(
      db,
      'lists',
      lastSyncTime,
      _mapList,
    );
    payload['tasks'] = await _getSyncTableRecords(
      db,
      'tasks',
      lastSyncTime,
      _mapTask,
    );
    payload['sessions'] = await _getSyncTableRecords(
      db,
      'sessions',
      lastSyncTime,
      _mapSession,
    );
    payload['task_recurrence_completions'] = await _getSyncTableRecords(
      db,
      'task_recurrence_completions',
      lastSyncTime,
      _mapRecurrenceCompletion,
    );

    // settings 特殊处理：排除同步配置相关的 key
    final syncKeys = [
      'syncServerUrl',
      'syncToken',
      'syncUserId',
      'lastSyncTime',
      'lastServerSyncCursor',
      'syncDir',
      'syncUsername',
      'syncFakePassword',
      'syncRealPassword',
      'deepseekApiKey',
    ];
    final settingsRecords = await db.query(
      'settings',
      where:
          'updated_at >= ? AND key NOT IN (${syncKeys.map((_) => '?').join(',')})',
      whereArgs: [lastSyncTime, ...syncKeys],
    );

    payload['settings'] = settingsRecords
        .map(
          (r) => {
            'id': r['key'],
            'updatedAt': r['updated_at'],
            'data': {'key': r['key'], 'value': r['value']},
          },
        )
        .toList();

    // 备忘录使用独立映射层和独立水位线：连接旧版服务器时备忘录负载会被
    // 跳过，任务水位线继续前进，备忘录的本地变更在服务器升级后仍可补传。
    // 服务端只保存 data 中的密文/元数据，不会尝试解密隐私内容。
    final memoPayload = await MemoDatabase.getSyncPayload(
      memoLastSyncTime ?? lastSyncTime,
    );
    payload.addAll(memoPayload);

    return payload;
  }

  static Future<List<Map<String, dynamic>>> _getSyncTableRecords(
    Database db,
    String table,
    int lastSyncTime,
    Map<String, dynamic> Function(Map<String, dynamic>) mapper,
  ) async {
    // 必须同时查询软删除记录（deleted = 1），否则删除操作无法跨设备同步
    final records = await db.query(
      table,
      // 包含水位边界，避免修改时间与同步开始时间落在同一毫秒时漏传。
      where: 'updated_at >= ? OR deleted = 1',
      whereArgs: [lastSyncTime],
    );
    final result = <Map<String, dynamic>>[];
    for (final r in records) {
      final mapped = mapper(r);
      // 系统日历事件 ID 是本机外部集成状态，不能跨设备同步。
      // Windows/macOS/Android 的日历事件 ID 不通用，远端覆盖会导致 Android
      // 失去本机旧事件引用，下一次刷新时新建事件并留下旧提醒。
      if (table == 'tasks') {
        final fieldVersions = await _getFieldVersions(
          db,
          'tasks',
          r['id'] as String,
        );
        mapped['_fieldUpdatedAt'] = {
          for (final fieldName in _taskSyncFields.keys)
            fieldName: fieldVersions[fieldName] ?? r['updated_at'],
        };
        mapped.remove('calendarEventId');
      }
      result.add({
        'id': r['id'],
        'updatedAt': r['updated_at'],
        'deleted': (r['deleted'] as int) == 1,
        'data': mapped,
      });
    }
    return result;
  }

  /// 应用从服务器下载的同步变更
  static Future<void> applySyncChanges(Map<String, dynamic> tables) async {
    final db = await database;
    await db.transaction((txn) async {
      // 任务必须先于清单处理。否则同批次的“移动任务 + 归档旧清单”会
      // 先把仍指向旧清单的本地任务错误级联归档。
      if (tables['tasks'] != null) {
        await _applyTableChanges(txn, 'tasks', tables['tasks'], _unmapTask);
      }
      if (tables['lists'] != null) {
        await _applyTableChanges(txn, 'lists', tables['lists'], _unmapList);
      }
      if (tables['sessions'] != null) {
        await _applyTableChanges(
          txn,
          'sessions',
          tables['sessions'],
          _unmapSession,
        );
      }
      if (tables['task_recurrence_completions'] != null) {
        await _applyTableChanges(
          txn,
          'task_recurrence_completions',
          tables['task_recurrence_completions'],
          _unmapRecurrenceCompletion,
        );
      }
      if (tables['settings'] != null) {
        await _applySettingsChanges(txn, tables['settings']);
      }
      await _repairMisappliedListArchives(txn);
    });

    // 备忘录表使用自己的字段映射和墓碑策略。放在主事务完成后应用，
    // 避免在 sqflite 事务中嵌套另一个 Database.transaction。
    await MemoDatabase.applySyncChanges(tables);
  }

  static Future<void> _applyTableChanges(
    Transaction txn,
    String table,
    dynamic records,
    Map<String, dynamic> Function(Map<String, dynamic>) unmapper,
  ) async {
    if (records is! List) return;
    for (final item in records) {
      final id = item['id'] as String;
      final remoteUpdatedAt = item['updatedAt'] as int? ?? 0;
      if (table == 'tasks') {
        await _applyTaskChange(txn, item);
        continue;
      }

      if (item['deleted'] == true) {
        final localRows = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [id],
          columns: ['updated_at'],
        );
        final localUpdatedAt = localRows.isEmpty
            ? 0
            : (localRows.first['updated_at'] as int? ?? 0);
        final data = item['data'] as Map<String, dynamic>?;
        final row = data == null ? <String, dynamic>{'id': id} : unmapper(data);
        row['updated_at'] = _maxTimestamp(localUpdatedAt, remoteUpdatedAt);
        row['deleted'] = 1;
        await txn.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (table == 'lists') {
          await _cascadeListDeleted(txn, id, row['updated_at'] as int);
        }
        continue;
      }

      final localRows = await txn.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        columns: table == 'lists' ? ['deleted', 'archived'] : ['deleted'],
      );
      if (localRows.isNotEmpty &&
          (localRows.first['deleted'] as int? ?? 0) == 1) {
        continue;
      }
      final localListWasArchived =
          table == 'lists' &&
          localRows.isNotEmpty &&
          (localRows.first['archived'] as int? ?? 0) == 1;

      final data = item['data'] as Map<String, dynamic>;
      final row = unmapper(data);
      row['updated_at'] = remoteUpdatedAt;
      row['deleted'] = 0;
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (table == 'lists') {
        final archived = (data['archived'] ?? false) == true;
        if (archived || localListWasArchived) {
          await _cascadeListArchived(
            txn,
            id,
            archived: archived,
            archivedAt: data['archivedAt'] as int?,
            updatedAt: remoteUpdatedAt,
          );
        }
      }
    }
  }

  static Future<void> _applyTaskChange(Transaction txn, dynamic item) async {
    final id = item['id'] as String;
    final remoteUpdatedAt = item['updatedAt'] as int? ?? 0;

    final localRows = await txn.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (item['deleted'] == true) {
      final data = Map<String, dynamic>.from(
        item['data'] as Map? ?? {'id': id},
      );
      final localUpdatedAt = localRows.isEmpty
          ? 0
          : (localRows.first['updated_at'] as int? ?? 0);
      final tombstoneUpdatedAt = _maxTimestamp(localUpdatedAt, remoteUpdatedAt);
      final row = _unmapTask(data);
      row['updated_at'] = tombstoneUpdatedAt;
      row['deleted'] = 1;
      row['calendar_event_id'] = localRows.isNotEmpty
          ? localRows.first['calendar_event_id']
          : null;
      await txn.insert(
        'tasks',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _setFieldVersions(
        txn,
        'tasks',
        id,
        _taskSyncFields.keys,
        tombstoneUpdatedAt,
      );
      return;
    }

    final data = Map<String, dynamic>.from(item['data'] as Map);
    final remoteVersions = _taskFieldVersionsFromData(data, remoteUpdatedAt);
    final mergedData = Map<String, dynamic>.from(data);
    final mergedVersions = Map<String, int>.from(remoteVersions);

    if (localRows.isNotEmpty) {
      final localRow = localRows.first;
      final localDeleted = (localRow['deleted'] as int? ?? 0) == 1;
      final localUpdatedAt = localRow['updated_at'] as int? ?? 0;
      if (localDeleted) return;

      final localVersions = await _getFieldVersions(txn, 'tasks', id);
      for (final fieldName in _taskSyncFields.keys) {
        final localFieldVersion = localVersions[fieldName] ?? localUpdatedAt;
        final remoteFieldVersion = remoteVersions[fieldName] ?? remoteUpdatedAt;
        if (localFieldVersion > remoteFieldVersion) {
          mergedData[fieldName] = _taskFieldValueFromRow(localRow, fieldName);
          mergedVersions[fieldName] = localFieldVersion;
        }
      }
    }

    final row = _unmapTask(mergedData);
    row['updated_at'] = [
      remoteUpdatedAt,
      ...mergedVersions.values,
    ].reduce((a, b) => a > b ? a : b);
    row['deleted'] = 0;

    final localCalendarEventId = localRows.isNotEmpty
        ? localRows.first['calendar_event_id']
        : null;
    row['calendar_event_id'] = localCalendarEventId;

    await txn.insert(
      'tasks',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final entry in mergedVersions.entries) {
      await txn.insert('sync_field_versions', {
        'table_name': 'tasks',
        'record_id': id,
        'field_name': entry.key,
        'updated_at': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static dynamic _taskFieldValueFromRow(
    Map<String, dynamic> row,
    String fieldName,
  ) {
    switch (fieldName) {
      case 'listId':
        return row['list_id'];
      case 'title':
        return row['title'];
      case 'notes':
        return row['notes'];
      case 'completed':
        return (row['completed'] as int? ?? 0) == 1;
      case 'completedAt':
        return row['completed_at'];
      case 'dueDate':
        return row['due_date'];
      case 'dueTime':
        return row['due_time'];
      case 'sortOrder':
        return row['sort_order'];
      case 'isMyDay':
        return (row['is_my_day'] as int? ?? 0) == 1;
      case 'myDayAddedAt':
        return row['my_day_added_at'];
      case 'recurrenceConfig':
        return row['recurrence_config'] != null
            ? _decodeJson(row['recurrence_config'] as String)
            : null;
      case 'expectedMinutes':
        return row['expected_minutes'];
      case 'isImportant':
        return (row['is_important'] as int? ?? 0) == 1;
      case 'reminderAt':
        return row['reminder_at'];
      case 'archived':
        return (row['archived'] as int? ?? 0) == 1;
      case 'archivedAt':
        return row['archived_at'];
      default:
        return null;
    }
  }

  static Future<void> _applySettingsChanges(
    Transaction txn,
    dynamic records,
  ) async {
    if (records is! List) return;
    const ignoreKeys = {
      'syncServerUrl',
      'syncToken',
      'syncUserId',
      'lastSyncTime',
      'lastServerSyncCursor',
      'syncDir',
      'syncUsername',
      'syncFakePassword',
      'syncRealPassword',
      'deepseekApiKey',
    };
    for (final item in records) {
      final data = item['data'] as Map<String, dynamic>;
      final key = data['key'] as String;
      if (ignoreKeys.contains(key)) continue;
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
      'icon_key': data['iconKey'] ?? 'list',
      'pinned': (data['pinned'] ?? false) ? 1 : 0,
      'top_order': data['topOrder'],
      'hidden': (data['hidden'] ?? false) ? 1 : 0,
      'created_at': data['createdAt'],
      'archived': (data['archived'] ?? false) ? 1 : 0,
      'archived_at': data['archivedAt'],
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
      'recurrence_config': data['recurrenceConfig'] != null
          ? _encodeJson(data['recurrenceConfig'])
          : null,
      'expected_minutes': data['expectedMinutes'],
      'is_important': (data['isImportant'] ?? false) ? 1 : 0,
      'reminder_at': data['reminderAt'],
      'calendar_event_id': data['calendarEventId'],
      'created_at': data['createdAt'],
      'archived': (data['archived'] ?? false) ? 1 : 0,
      'archived_at': data['archivedAt'],
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

  static Map<String, dynamic> _unmapRecurrenceCompletion(
    Map<String, dynamic> data,
  ) {
    return {
      'id': data['id'],
      'task_id': data['taskId'],
      'completion_date': data['completionDate'],
      'completed_at': data['completedAt'],
      'created_at': data['createdAt'],
    };
  }

  static const _backupTables = <String>[
    'lists',
    'tasks',
    'sessions',
    'task_recurrence_completions',
    'settings',
    'sync_field_versions',
    'ai_conversations',
    'ai_messages',
    'ai_operations',
    ...MemoDatabase.syncTables,
  ];

  static const _backupTableClearOrder = <String>[
    'memo_shares',
    'memo_attachments',
    'memo_versions',
    'memo_tag_links',
    'memos',
    'memo_tags',
    'memo_folders',
    'privacy_vault',
    'ai_operations',
    'ai_messages',
    'ai_conversations',
    'sync_field_versions',
    'task_recurrence_completions',
    'sessions',
    'tasks',
    'lists',
    'settings',
  ];

  static const _backupExcludedSettings = <String>{
    'syncServerUrl',
    'syncToken',
    'syncUserId',
    'lastSyncTime',
    'lastServerSyncCursor',
    'syncDir',
    'syncUsername',
    'syncFakePassword',
    'syncRealPassword',
    'deepseekApiKey',
  };

  static const _backupRequiredTables = <String>{
    'lists',
    'tasks',
    'sessions',
    'task_recurrence_completions',
    'settings',
    'sync_field_versions',
    'ai_conversations',
    'ai_messages',
    'ai_operations',
    ...MemoDatabase.syncTables,
  };

  /// 跨平台备份格式。浏览器通过 JSON 下载，原生端可在后续版本复用。
  static Future<Map<String, dynamic>> exportBackup() async {
    final db = await database;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _backupTables) {
      final rows = await db.query(table);
      final normalizedRows = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (table == 'settings') {
        normalizedRows.removeWhere(
          (row) => _backupExcludedSettings.contains(row['key']),
        );
      }
      tables[table] = normalizedRows;
    }
    return {
      'format': 'focus-my-time-backup',
      'version': _schemaVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'tables': tables,
    };
  }

  /// 用跨平台 JSON 备份恢复数据。认证令牌与 AI 密钥不会包含在备份中。
  static Future<void> importBackup(Map<String, dynamic> backup) async {
    if (backup['format'] != 'focus-my-time-backup') {
      throw const FormatException('不是 FocusMyTime 备份文件');
    }
    final version = backup['version'];
    if (version is! int || version < 1 || version > _schemaVersion) {
      throw const FormatException('备份版本不受支持');
    }
    final rawTables = backup['tables'];
    if (rawTables is! Map) {
      throw const FormatException('备份缺少数据表');
    }

    final missingTables = _backupRequiredTables
        .where((table) => !rawTables.containsKey(table))
        .toList();
    if (missingTables.isNotEmpty) {
      throw FormatException('备份缺少必要数据表: ${missingTables.join(', ')}');
    }

    // Fully normalize and validate the shape before opening a transaction.
    // A malformed backup must never reach the destructive clear phase.
    final validatedTables = <String, List<Map<String, dynamic>>>{};
    for (final table in _backupTables) {
      final rawRows = rawTables[table];
      if (rawRows is! List) {
        throw FormatException('备份中的 $table 数据无效');
      }
      final rows = <Map<String, dynamic>>[];
      for (final rawRow in rawRows) {
        if (rawRow is! Map) {
          throw FormatException('备份中的 $table 记录无效');
        }
        final row = <String, dynamic>{};
        for (final entry in rawRow.entries) {
          if (entry.key is! String) {
            throw FormatException('备份中的 $table 记录字段无效');
          }
          row[entry.key as String] = entry.value;
        }
        rows.add(row);
      }
      validatedTables[table] = rows;
    }

    const requiredSystemListIds = {
      'system-my-day',
      'system-important',
      'system-all-tasks',
    };
    final backupListIds = validatedTables['lists']!
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    final missingSystemLists = requiredSystemListIds.difference(backupListIds);
    if (missingSystemLists.isNotEmpty) {
      throw FormatException('备份缺少系统清单: ${missingSystemLists.join(', ')}');
    }

    final db = await database;
    await db.transaction((txn) async {
      final privateSettings = await txn.query(
        'settings',
        where:
            'key IN (${List.filled(_backupExcludedSettings.length, '?').join(', ')})',
        whereArgs: _backupExcludedSettings.toList(),
      );

      for (final table in _backupTableClearOrder) {
        await txn.delete(table);
      }
      for (final table in _backupTables) {
        for (final row in validatedTables[table]!) {
          if (table == 'settings' &&
              _backupExcludedSettings.contains(row['key'])) {
            continue;
          }
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // Authentication tokens, sync cursors and API secrets are device-local.
      // They are excluded from exported files and must survive a restore.
      for (final row in privateSettings) {
        await txn.insert(
          'settings',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final key in const ['lastSyncTime', 'lastServerSyncCursor']) {
        await txn.insert('settings', {
          'key': key,
          'value': '0',
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<Map<String, dynamic>> getDebugInfo() async {
    final db = await database;
    final listsCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM lists'),
        ) ??
        0;
    final tasksCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks'),
        ) ??
        0;
    final sessionsCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sessions'),
        ) ??
        0;
    final dbPath = kIsWeb ? '浏览器 IndexedDB' : await getDatabasesPath();
    return {
      'dbOpen': true,
      'lists': listsCount,
      'tasks': tasksCount,
      'sessions': sessionsCount,
      'dbPath': '$dbPath/focus_my_time.db',
    };
  }

  static Future<String> getDbPath() async {
    if (kIsWeb) return 'focus_my_time.db';
    final dbPath = await getDatabasesPath();
    return '$dbPath/focus_my_time.db';
  }

  static Future<Map<String, dynamic>> runDownloadTest() async {
    // Simulated test download - in production this would actually test the sync
    final lists = await getLists();
    final tasks = await getAllTasks();
    return {'listsCount': lists.length, 'tasksCount': tasks.length};
  }

  // ========== AI 对话 ==========

  static Future<Map<String, dynamic>> createAiConversation({
    String? title,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'conv-${_uuid.v4()}';
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
    await db.update(
      'ai_conversations',
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getAiConversations() async {
    final db = await database;
    final result = await db.query(
      'ai_conversations',
      where: 'deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return result
        .map(
          (r) => {
            'id': r['id'],
            'title': r['title'],
            'createdAt': r['created_at'],
            'updatedAt': r['updated_at'],
          },
        )
        .toList();
  }

  static Future<void> deleteAiConversation(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'ai_messages',
      {'deleted': 1, 'updated_at': now},
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await db.update(
      'ai_operations',
      {'deleted': 1, 'updated_at': now},
      where:
          'message_id IN (SELECT id FROM ai_messages WHERE conversation_id = ?)',
      whereArgs: [id],
    );
    await db.update(
      'ai_conversations',
      {'deleted': 1, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final id = 'msg-${_uuid.v4()}';
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

  static Future<List<Map<String, dynamic>>> getAiMessages(
    String conversationId,
  ) async {
    final db = await database;
    final result = await db.query(
      'ai_messages',
      where: 'conversation_id = ? AND deleted = 0',
      whereArgs: [conversationId],
      orderBy: 'created_at',
    );
    return result
        .map(
          (r) => {
            'id': r['id'],
            'conversationId': r['conversation_id'],
            'role': r['role'],
            'content': r['content'],
            'toolCallsJson': r['tool_calls_json'],
            'createdAt': r['created_at'],
          },
        )
        .toList();
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
    final id = 'aio-${_uuid.v4()}';
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

  static Future<List<Map<String, dynamic>>> getAiOperations(
    String messageId,
  ) async {
    final db = await database;
    final result = await db.query(
      'ai_operations',
      where: 'message_id = ? AND deleted = 0',
      whereArgs: [messageId],
      orderBy: 'created_at',
    );
    return result
        .map(
          (r) => {
            'id': r['id'],
            'messageId': r['message_id'],
            'type': r['type'],
            'paramsJson': r['params_json'],
            'summary': r['summary'],
            'reasoning': r['reasoning'],
            'status': r['status'],
            'errorMessage': r['error_message'],
            'createdAt': r['created_at'],
          },
        )
        .toList();
  }

  static Future<void> updateAiOperationStatus(
    String id,
    String status, {
    String? errorMessage,
  }) async {
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
