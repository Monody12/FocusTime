import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:focus_my_time/data/database/app_database.dart';

/// Local persistence for the memo feature.
///
/// Memo tables intentionally live beside the task tables in AppDatabase, but
/// this class owns their mapping and CRUD surface.  The UI never writes SQL
/// directly, which keeps soft-delete, version retention, and sync mapping in
/// one place.
class MemoDatabase {
  static const _uuid = Uuid();
  static const vaultId = 'privacy-vault';
  static const maxFolderDepth = 10;
  static const maxHistoryVersions = 20;

  static const syncTables = <String>[
    'memo_folders',
    'memo_tags',
    'memos',
    'memo_tag_links',
    'memo_versions',
    'memo_attachments',
    'memo_shares',
    'privacy_vault',
  ];

  static Future<Database> get _db => AppDatabase.database;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static String _id(String prefix) => '$prefix-${_uuid.v4()}';

  static bool _asBool(Object? value) => value is bool
      ? value
      : value is num
      ? value != 0
      : value?.toString().toLowerCase() == 'true';

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _mapRow(String table, Map<String, dynamic> row) {
    switch (table) {
      case 'memo_folders':
        return {
          'id': row['id'],
          'parentId': row['parent_id'],
          'name': row['name'],
          'sortOrder': row['sort_order'],
          'archived': _asBool(row['archived']),
          'archivedAt': row['archived_at'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memo_tags':
        return {
          'id': row['id'],
          'name': row['name'],
          'color': row['color'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memos':
        return {
          'id': row['id'],
          'folderId': row['folder_id'],
          'title': row['title'],
          'bodyMd': row['body_md'],
          'isPrivate': _asBool(row['is_private']),
          'encryptTitle': _asBool(row['encrypt_title']),
          'encryptedPayload': row['encrypted_payload'],
          'cryptoVersion': row['crypto_version'],
          'pinned': _asBool(row['pinned']),
          'archived': _asBool(row['archived']),
          'archivedAt': row['archived_at'],
          'aiAllowed': _asBool(row['ai_allowed']),
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memo_tag_links':
        return {
          'id': row['id'],
          'memoId': row['memo_id'],
          'tagId': row['tag_id'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memo_versions':
        return {
          'id': row['id'],
          'memoId': row['memo_id'],
          'versionNumber': row['version_number'],
          'title': row['title'],
          'bodyMd': row['body_md'],
          'encryptedPayload': row['encrypted_payload'],
          'isPrivate': _asBool(row['is_private']),
          'pinned': _asBool(row['pinned']),
          'source': row['source'] ?? 'manual',
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memo_attachments':
        return {
          'id': row['id'],
          'memoId': row['memo_id'],
          'versionId': row['version_id'],
          'filename': row['filename'],
          'mimeType': row['mime_type'],
          'sizeBytes': row['size_bytes'],
          'storageKey': row['storage_key'],
          'sha256': row['sha256'],
          'isPrivate': _asBool(row['is_private']),
          'encryptedPayload': row['encrypted_payload'],
          'uploadStatus': row['upload_status'],
          'width': row['width'],
          'height': row['height'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'memo_shares':
        return {
          'id': row['id'],
          'attachmentId': row['attachment_id'],
          'shareKind': row['share_kind'],
          'tokenHash': row['token_hash'],
          'expiresAt': row['expires_at'],
          'passwordHash': row['password_hash'],
          'publicStorageKey': row['public_storage_key'],
          'revoked': _asBool(row['revoked']),
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      case 'privacy_vault':
        return {
          'id': row['id'],
          'kdfName': row['kdf_name'],
          'kdfParams': row['kdf_params'],
          'salt': row['salt'],
          'wrappedMasterKey': row['wrapped_master_key'],
          'wrapNonce': row['wrap_nonce'],
          'recoveryWrappedMasterKey': row['recovery_wrapped_master_key'],
          'recoveryNonce': row['recovery_nonce'],
          'cryptoVersion': row['crypto_version'],
          'configRevision': row['config_revision'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
        };
      default:
        return Map<String, dynamic>.from(row);
    }
  }

  static Map<String, dynamic> _unmapRow(
    String table,
    Map<String, dynamic> data,
  ) {
    bool flag(String key) => _asBool(data[key]);
    switch (table) {
      case 'memo_folders':
        return {
          'id': data['id'],
          'parent_id': data['parentId'],
          'name': data['name'] ?? '',
          'sort_order': data['sortOrder'] ?? 0,
          'archived': flag('archived') ? 1 : 0,
          'archived_at': data['archivedAt'],
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memo_tags':
        return {
          'id': data['id'],
          'name': data['name'] ?? '',
          'color': data['color'],
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memos':
        return {
          'id': data['id'],
          'folder_id': data['folderId'],
          'title': data['title'],
          'body_md': data['bodyMd'],
          'is_private': flag('isPrivate') ? 1 : 0,
          'encrypt_title': flag('encryptTitle') ? 1 : 0,
          'encrypted_payload': data['encryptedPayload'],
          'crypto_version': data['cryptoVersion'] ?? 1,
          'pinned': flag('pinned') ? 1 : 0,
          'archived': flag('archived') ? 1 : 0,
          'archived_at': data['archivedAt'],
          'ai_allowed': flag('aiAllowed') ? 1 : 0,
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memo_tag_links':
        return {
          'id': data['id'],
          'memo_id': data['memoId'],
          'tag_id': data['tagId'],
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memo_versions':
        return {
          'id': data['id'],
          'memo_id': data['memoId'],
          'version_number': data['versionNumber'] ?? 1,
          'title': data['title'],
          'body_md': data['bodyMd'],
          'encrypted_payload': data['encryptedPayload'],
          'is_private': flag('isPrivate') ? 1 : 0,
          'pinned': flag('pinned') ? 1 : 0,
          'source': data['source'] ?? 'manual',
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memo_attachments':
        return {
          'id': data['id'],
          'memo_id': data['memoId'],
          'version_id': data['versionId'],
          'filename': data['filename'],
          'mime_type': data['mimeType'] ?? 'application/octet-stream',
          'size_bytes': data['sizeBytes'] ?? 0,
          'storage_key': data['storageKey'],
          'sha256': data['sha256'],
          'is_private': flag('isPrivate') ? 1 : 0,
          'encrypted_payload': data['encryptedPayload'],
          'upload_status': data['uploadStatus'] ?? 'pending',
          'width': data['width'],
          'height': data['height'],
          'created_at': data['createdAt'] ?? 0,
        };
      case 'memo_shares':
        return {
          'id': data['id'],
          'attachment_id': data['attachmentId'],
          'share_kind': data['shareKind'] ?? 'encrypted',
          'token_hash': data['tokenHash'] ?? '',
          'expires_at': data['expiresAt'],
          'password_hash': data['passwordHash'],
          'public_storage_key': data['publicStorageKey'],
          'revoked': flag('revoked') ? 1 : 0,
          'created_at': data['createdAt'] ?? 0,
        };
      case 'privacy_vault':
        return {
          'id': data['id'] ?? vaultId,
          'kdf_name': data['kdfName'] ?? 'argon2id',
          'kdf_params': data['kdfParams'] ?? '{}',
          'salt': data['salt'] ?? '',
          'wrapped_master_key': data['wrappedMasterKey'] ?? '',
          'wrap_nonce': data['wrapNonce'] ?? '',
          'recovery_wrapped_master_key': data['recoveryWrappedMasterKey'] ?? '',
          'recovery_nonce': data['recoveryNonce'] ?? '',
          'crypto_version': data['cryptoVersion'] ?? 1,
          'config_revision': data['configRevision'] ?? 1,
          'created_at': data['createdAt'] ?? 0,
        };
      default:
        return Map<String, dynamic>.from(data);
    }
  }

  static Future<List<Map<String, dynamic>>> getFolders({
    String? parentId,
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final where = StringBuffer('deleted = 0');
    final args = <Object?>[];
    if (parentId == null) {
      where.write(' AND parent_id IS NULL');
    } else {
      where.write(' AND parent_id = ?');
      args.add(parentId);
    }
    if (!includeArchived) {
      where.write(' AND archived = 0');
    }
    final rows = await db.query(
      'memo_folders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'sort_order, name COLLATE NOCASE',
    );
    return rows.map((row) => _mapRow('memo_folders', row)).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllFolders({
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'memo_folders',
      where: includeDeleted ? null : 'deleted = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((row) => _mapRow('memo_folders', row)).toList();
  }

  static Future<int> _folderDepth(DatabaseExecutor db, String? parentId) async {
    var depth = 0;
    var current = parentId;
    final visited = <String>{};
    while (current != null && current.isNotEmpty) {
      if (!visited.add(current)) {
        throw const FormatException('文件夹层级存在循环引用');
      }
      final rows = await db.query(
        'memo_folders',
        columns: ['parent_id'],
        where: 'id = ? AND deleted = 0',
        whereArgs: [current],
        limit: 1,
      );
      if (rows.isEmpty) throw const FormatException('父文件夹不存在');
      depth++;
      current = rows.first['parent_id'] as String?;
      if (depth > maxFolderDepth) break;
    }
    return depth;
  }

  static Future<Map<String, dynamic>> createFolder(
    String name, {
    String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('文件夹名称不能为空');
    final db = await _db;
    final depth = await _folderDepth(db, parentId);
    if (depth >= maxFolderDepth) {
      throw const FormatException('文件夹最多支持 10 层');
    }
    final duplicate = await db.query(
      'memo_folders',
      where: 'deleted = 0 AND parent_id IS ? AND name = ? COLLATE NOCASE',
      whereArgs: [parentId, trimmed],
      limit: 1,
    );
    if (duplicate.isNotEmpty) throw const FormatException('同级文件夹名称已存在');
    final now = _now();
    final row = {
      'id': _id('memo-folder'),
      'parent_id': parentId,
      'name': trimmed,
      'sort_order': 0,
      'archived': 0,
      'archived_at': null,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    await db.insert('memo_folders', row);
    return _mapRow('memo_folders', row);
  }

  static Future<void> updateFolder(
    String id, {
    String? name,
    String? parentId,
    bool? archived,
    bool clearParent = false,
  }) async {
    final db = await _db;
    final updates = <String, Object?>{};
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw const FormatException('文件夹名称不能为空');
      updates['name'] = trimmed;
    }
    if (parentId != null || clearParent) {
      if (parentId == null) {
        updates['parent_id'] = null;
      } else {
        if (parentId == id) throw const FormatException('文件夹不能移动到自身');
        final depth = await _folderDepth(db, parentId);
        if (depth >= maxFolderDepth) {
          throw const FormatException('文件夹最多支持 10 层');
        }
        String? current = parentId;
        while (current != null) {
          if (current == id) throw const FormatException('文件夹不能移动到其子文件夹');
          final rows = await db.query(
            'memo_folders',
            columns: ['parent_id'],
            where: 'id = ? AND deleted = 0',
            whereArgs: [current],
            limit: 1,
          );
          current = rows.isEmpty ? null : rows.first['parent_id'] as String?;
        }
        updates['parent_id'] = parentId;
      }
    }
    if (archived != null) {
      updates['archived'] = archived ? 1 : 0;
      updates['archived_at'] = archived ? _now() : null;
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = _now();
    await db.update(
      'memo_folders',
      updates,
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  static Future<void> deleteFolder(String id) async {
    final db = await _db;
    await db.update(
      'memo_folders',
      {'deleted': 1, 'updated_at': _now()},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> getTags() async {
    final db = await _db;
    final rows = await db.query(
      'memo_tags',
      where: 'deleted = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((row) => _mapRow('memo_tags', row)).toList();
  }

  static Future<Map<String, dynamic>> createTag(
    String name, {
    int? color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('标签名称不能为空');
    final db = await _db;
    final duplicate = await db.query(
      'memo_tags',
      where: 'deleted = 0 AND name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (duplicate.isNotEmpty) throw const FormatException('标签名称已存在');
    final now = _now();
    final row = {
      'id': _id('memo-tag'),
      'name': trimmed,
      'color': color,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    await db.insert('memo_tags', row);
    return _mapRow('memo_tags', row);
  }

  static Future<void> deleteTag(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = _now();
      await txn.update(
        'memo_tags',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ? AND deleted = 0',
        whereArgs: [id],
      );
      await txn.update(
        'memo_tag_links',
        {'deleted': 1, 'updated_at': now},
        where: 'tag_id = ? AND deleted = 0',
        whereArgs: [id],
      );
    });
  }

  static Future<List<Map<String, dynamic>>> getMemos({
    String? folderId,
    String? query,
    bool includeArchived = false,
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) {
      conditions.add('m.deleted = 0');
    }
    if (!includeArchived) conditions.add('m.archived = 0');
    if (folderId != null) {
      conditions.add('m.folder_id = ?');
      args.add(folderId);
    }
    if (query != null && query.trim().isNotEmpty) {
      conditions.add('(m.title LIKE ? OR m.body_md LIKE ?)');
      final pattern = '%${query.trim()}%';
      args.addAll([pattern, pattern]);
    }
    final rows = await db.rawQuery('''
      SELECT m.*, f.name AS folder_name
      FROM memos m
      LEFT JOIN memo_folders f ON f.id = m.folder_id AND f.deleted = 0
      ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
      ORDER BY m.pinned DESC, m.updated_at DESC
    ''', args);
    return rows.map((row) {
      final mapped = _mapRow('memos', row);
      mapped['folderName'] = row['folder_name'];
      return mapped;
    }).toList();
  }

  static Future<Map<String, dynamic>?> getMemo(String id) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT m.*, f.name AS folder_name
      FROM memos m
      LEFT JOIN memo_folders f ON f.id = m.folder_id AND f.deleted = 0
      WHERE m.id = ?
      LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    final mapped = _mapRow('memos', rows.first);
    mapped['folderName'] = rows.first['folder_name'];
    mapped['tags'] = await getMemoTags(id);
    return mapped;
  }

  static Future<Map<String, dynamic>> createMemo({
    String title = '未命名备忘录',
    String bodyMd = '',
    String? folderId,
    bool isPrivate = false,
    bool encryptTitle = false,
    String? encryptedPayload,
    int cryptoVersion = 1,
    bool aiAllowed = false,
  }) async {
    final now = _now();
    final db = await _db;
    final id = _id('memo');
    final row = {
      'id': id,
      'folder_id': folderId,
      'title': isPrivate && encryptTitle ? null : title,
      'body_md': isPrivate ? null : bodyMd,
      'is_private': isPrivate ? 1 : 0,
      'encrypt_title': encryptTitle ? 1 : 0,
      'encrypted_payload': encryptedPayload,
      'crypto_version': cryptoVersion,
      'pinned': 0,
      'archived': 0,
      'archived_at': null,
      'ai_allowed': aiAllowed ? 1 : 0,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    await db.insert('memos', row);
    return _mapRow('memos', row);
  }

  static Future<void> updateMemo(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final db = await _db;
    final mapped = <String, Object?>{};
    if (updates.containsKey('folderId')) {
      mapped['folder_id'] = updates['folderId'];
    }
    if (updates.containsKey('title')) mapped['title'] = updates['title'];
    if (updates.containsKey('bodyMd')) mapped['body_md'] = updates['bodyMd'];
    if (updates.containsKey('isPrivate')) {
      mapped['is_private'] = _asBool(updates['isPrivate']) ? 1 : 0;
    }
    if (updates.containsKey('encryptTitle')) {
      mapped['encrypt_title'] = _asBool(updates['encryptTitle']) ? 1 : 0;
    }
    if (updates.containsKey('encryptedPayload')) {
      mapped['encrypted_payload'] = updates['encryptedPayload'];
    }
    if (updates.containsKey('cryptoVersion')) {
      mapped['crypto_version'] = updates['cryptoVersion'];
    }
    if (updates.containsKey('pinned')) {
      mapped['pinned'] = _asBool(updates['pinned']) ? 1 : 0;
    }
    if (updates.containsKey('archived')) {
      final archived = _asBool(updates['archived']);
      mapped['archived'] = archived ? 1 : 0;
      mapped['archived_at'] = archived ? _now() : null;
    }
    if (updates.containsKey('aiAllowed')) {
      mapped['ai_allowed'] = _asBool(updates['aiAllowed']) ? 1 : 0;
    }
    if (mapped.isEmpty) {
      return;
    }
    mapped['updated_at'] = _now();
    await db.update(
      'memos',
      mapped,
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  static Future<void> deleteMemo(String id) async {
    final db = await _db;
    final now = _now();
    await db.transaction((txn) async {
      await txn.update(
        'memos',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ? AND deleted = 0',
        whereArgs: [id],
      );
      await txn.update(
        'memo_tag_links',
        {'deleted': 1, 'updated_at': now},
        where: 'memo_id = ? AND deleted = 0',
        whereArgs: [id],
      );
    });
  }

  static Future<void> restoreMemo(String id) async {
    final db = await _db;
    await db.update(
      'memos',
      {'deleted': 0, 'archived': 0, 'archived_at': null, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 回收站清理：物理删除备忘录行、版本历史和标签关系。
  /// 附件记录保留，由附件使用统计决定后续清理。
  static Future<void> purgeMemo(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('memos', where: 'id = ?', whereArgs: [id]);
      await txn.delete('memo_versions', where: 'memo_id = ?', whereArgs: [id]);
      await txn.delete('memo_tag_links', where: 'memo_id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Map<String, dynamic>>> getMemoTags(String memoId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT t.*
      FROM memo_tags t
      INNER JOIN memo_tag_links l ON l.tag_id = t.id
      WHERE l.memo_id = ? AND l.deleted = 0 AND t.deleted = 0
      ORDER BY t.name COLLATE NOCASE
    ''',
      [memoId],
    );
    return rows.map((row) => _mapRow('memo_tags', row)).toList();
  }

  static Future<void> setMemoTags(String memoId, List<String> tagIds) async {
    final db = await _db;
    final now = _now();
    await db.transaction((txn) async {
      await txn.update(
        'memo_tag_links',
        {'deleted': 1, 'updated_at': now},
        where: 'memo_id = ? AND deleted = 0',
        whereArgs: [memoId],
      );
      for (final tagId in tagIds.toSet()) {
        await txn.insert('memo_tag_links', {
          'id': _id('memo-tag-link'),
          'memo_id': memoId,
          'tag_id': tagId,
          'created_at': now,
          'updated_at': now,
          'deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<Map<String, dynamic>?> createVersion(
    String memoId, {
    String? title,
    String? bodyMd,
    String? encryptedPayload,
    bool isPrivate = false,
    bool pinned = false,
    String source = 'manual',
  }) async {
    final db = await _db;
    final now = _now();
    final current = await db.rawQuery(
      'SELECT COALESCE(MAX(version_number), 0) AS value FROM memo_versions WHERE memo_id = ?',
      [memoId],
    );
    final versionNumber = ((current.first['value'] as num?)?.toInt() ?? 0) + 1;
    final row = {
      'id': _id('memo-version'),
      'memo_id': memoId,
      'version_number': versionNumber,
      'title': isPrivate ? null : title,
      'body_md': isPrivate ? null : bodyMd,
      'encrypted_payload': isPrivate ? encryptedPayload : null,
      'is_private': isPrivate ? 1 : 0,
      'pinned': pinned ? 1 : 0,
      'source': source,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    await db.insert('memo_versions', row);
    await pruneVersions(memoId, source: source);
    return _mapRow('memo_versions', row);
  }

  static Future<List<Map<String, dynamic>>> getVersions(String memoId) async {
    final db = await _db;
    final rows = await db.query(
      'memo_versions',
      where: 'memo_id = ? AND deleted = 0',
      whereArgs: [memoId],
      orderBy: 'version_number DESC',
    );
    return rows.map((row) => _mapRow('memo_versions', row)).toList();
  }

  static Future<void> pruneVersions(
    String memoId, {
    String source = 'manual',
  }) async {
    final db = await _db;
    final rows = await db.query(
      'memo_versions',
      columns: ['id', 'pinned', 'version_number'],
      where: 'memo_id = ? AND deleted = 0 AND source = ?',
      whereArgs: [memoId, source],
      orderBy: 'pinned DESC, version_number DESC',
    );
    final limit = source == 'auto' ? 10 : maxHistoryVersions;
    if (rows.length <= limit) return;
    final keep = rows.take(limit).map((row) => row['id']).toSet();
    final now = _now();
    for (final row in rows.skip(limit)) {
      if (!keep.contains(row['id'])) {
        await db.update(
          'memo_versions',
          {'deleted': 1, 'updated_at': now},
          where: 'id = ? AND deleted = 0',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getAttachments({
    String? memoId,
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) conditions.add('deleted = 0');
    if (memoId != null) {
      conditions.add('memo_id = ?');
      args.add(memoId);
    }
    final rows = await db.query(
      'memo_attachments',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => _mapRow('memo_attachments', row)).toList();
  }

  static Future<Map<String, dynamic>> createAttachment({
    String? memoId,
    String? versionId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
    String? storageKey,
    String? sha256,
    bool isPrivate = false,
    String? encryptedPayload,
    String uploadStatus = 'pending',
    int? width,
    int? height,
  }) async {
    if (sizeBytes < 0) throw const FormatException('附件大小无效');
    final now = _now();
    final row = {
      'id': _id('memo-attachment'),
      'memo_id': memoId,
      'version_id': versionId,
      'filename': isPrivate ? null : filename,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'storage_key': storageKey,
      'sha256': sha256,
      'is_private': isPrivate ? 1 : 0,
      'encrypted_payload': encryptedPayload,
      'upload_status': uploadStatus,
      'width': width,
      'height': height,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    final db = await _db;
    await db.insert('memo_attachments', row);
    return _mapRow('memo_attachments', row);
  }

  static Future<void> updateAttachment(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final db = await _db;
    final mapped = <String, Object?>{};
    const fields = {
      'memoId': 'memo_id',
      'versionId': 'version_id',
      'filename': 'filename',
      'mimeType': 'mime_type',
      'sizeBytes': 'size_bytes',
      'storageKey': 'storage_key',
      'sha256': 'sha256',
      'encryptedPayload': 'encrypted_payload',
      'uploadStatus': 'upload_status',
      'width': 'width',
      'height': 'height',
    };
    for (final entry in fields.entries) {
      if (updates.containsKey(entry.key)) {
        mapped[entry.value] = updates[entry.key];
      }
    }
    if (updates.containsKey('isPrivate')) {
      mapped['is_private'] = _asBool(updates['isPrivate']) ? 1 : 0;
    }
    if (updates.containsKey('deleted')) {
      mapped['deleted'] = _asBool(updates['deleted']) ? 1 : 0;
    }
    if (mapped.isEmpty) return;
    mapped['updated_at'] = _now();
    await db.update(
      'memo_attachments',
      mapped,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<Map<String, dynamic>> getAttachmentUsage() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN deleted = 0 THEN size_bytes ELSE 0 END), 0) AS active_bytes,
        COALESCE(SUM(CASE WHEN deleted = 1 THEN size_bytes ELSE 0 END), 0) AS deleted_bytes,
        COUNT(CASE WHEN deleted = 0 THEN 1 END) AS active_count,
        COUNT(CASE WHEN deleted = 1 THEN 1 END) AS deleted_count
      FROM memo_attachments
    ''');
    final row = rows.first;
    return {
      'activeBytes': (row['active_bytes'] as num?)?.toInt() ?? 0,
      'deletedBytes': (row['deleted_bytes'] as num?)?.toInt() ?? 0,
      'activeCount': (row['active_count'] as num?)?.toInt() ?? 0,
      'deletedCount': (row['deleted_count'] as num?)?.toInt() ?? 0,
    };
  }

  static Future<Map<String, dynamic>?> getAttachment(String id) async {
    final db = await _db;
    final rows = await db.query(
      'memo_attachments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapRow('memo_attachments', rows.first);
  }

  static Future<Map<String, dynamic>?> getVault() async {
    final db = await _db;
    final rows = await db.query(
      'privacy_vault',
      where: 'id = ? AND deleted = 0',
      whereArgs: [vaultId],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapRow('privacy_vault', rows.first);
  }

  static Future<void> saveVault(Map<String, dynamic> values) async {
    final db = await _db;
    final now = _now();
    final existing = await db.query(
      'privacy_vault',
      where: 'id = ?',
      whereArgs: [vaultId],
      limit: 1,
    );
    final data = _unmapRow('privacy_vault', {
      ...values,
      'id': vaultId,
      'createdAt':
          values['createdAt'] ??
          (existing.isEmpty ? now : existing.first['created_at']),
    });
    data['updated_at'] = now;
    data['deleted'] = 0;
    await db.insert(
      'privacy_vault',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Builds client sync records for all memo tables.  Memo data is already
  /// encrypted where required; the server only stores the opaque `data` map.
  static Future<Map<String, List<Map<String, dynamic>>>> getSyncPayload(
    int lastSyncTime,
  ) async {
    final db = await _db;
    final payload = <String, List<Map<String, dynamic>>>{};
    for (final table in syncTables) {
      final rows = await db.query(
        table,
        where: 'updated_at >= ? OR deleted = 1',
        whereArgs: [lastSyncTime],
      );
      payload[table] = rows.map((row) {
        final mapped = _mapRow(table, row);
        return {
          'id': row['id'],
          'updatedAt': row['updated_at'],
          'deleted': _asBool(row['deleted']),
          'data': mapped,
        };
      }).toList();
    }
    return payload;
  }

  /// Applies server memo records in one transaction.  Tombstones are kept so
  /// a later offline device cannot resurrect deleted content.
  static Future<void> applySyncChanges(Map<String, dynamic> tables) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final table in syncTables) {
        final records = tables[table];
        if (records is! List) continue;
        for (final rawItem in records) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final id = item['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final remoteUpdatedAt = _asInt(item['updatedAt']) ?? 0;
          final localRows = await txn.query(
            table,
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          final localUpdatedAt = localRows.isEmpty
              ? 0
              : (_asInt(localRows.first['updated_at']) ?? 0);
          if (remoteUpdatedAt < localUpdatedAt) continue;

          final deleted = item['deleted'] == true;
          final rawData = item['data'];
          final data = rawData is Map
              ? Map<String, dynamic>.from(rawData)
              : <String, dynamic>{'id': id};
          if (deleted) {
            if (localRows.isNotEmpty) {
              await txn.update(
                table,
                {'deleted': 1, 'updated_at': remoteUpdatedAt},
                where: 'id = ?',
                whereArgs: [id],
              );
            } else {
              final tombstone = _tombstoneRow(table, id, remoteUpdatedAt);
              await txn.insert(
                table,
                tombstone,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            continue;
          }

          final row = _unmapRow(table, {...data, 'id': id});
          row['updated_at'] = remoteUpdatedAt;
          row['deleted'] = 0;
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  static Map<String, dynamic> _tombstoneRow(
    String table,
    String id,
    int updatedAt,
  ) {
    final base = <String, dynamic>{
      'id': id,
      'created_at': updatedAt,
      'updated_at': updatedAt,
      'deleted': 1,
    };
    switch (table) {
      case 'memo_folders':
        return {...base, 'name': '', 'sort_order': 0, 'archived': 0};
      case 'memo_tags':
        return {...base, 'name': ''};
      case 'memos':
        return {
          ...base,
          'title': null,
          'body_md': null,
          'is_private': 0,
          'encrypt_title': 0,
          'crypto_version': 1,
          'pinned': 0,
          'archived': 0,
          'ai_allowed': 0,
        };
      case 'memo_tag_links':
        return {...base, 'memo_id': '', 'tag_id': ''};
      case 'memo_versions':
        return {
          ...base,
          'memo_id': '',
          'version_number': 0,
          'is_private': 0,
          'pinned': 0,
        };
      case 'memo_attachments':
        return {
          ...base,
          'mime_type': 'application/octet-stream',
          'size_bytes': 0,
          'is_private': 0,
          'upload_status': 'deleted',
        };
      case 'memo_shares':
        return {
          ...base,
          'attachment_id': '',
          'share_kind': 'encrypted',
          'token_hash': '',
          'revoked': 1,
        };
      case 'privacy_vault':
        return {
          ...base,
          'kdf_name': 'argon2id',
          'kdf_params': '{}',
          'salt': '',
          'wrapped_master_key': '',
          'wrap_nonce': '',
          'recovery_wrapped_master_key': '',
          'recovery_nonce': '',
          'crypto_version': 1,
          'config_revision': 1,
        };
      default:
        return base;
    }
  }
}
