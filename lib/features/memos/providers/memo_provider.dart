import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/core/utils/debug_error_reporter.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/services/memo_escrow_service.dart';
import 'package:focus_my_time/features/memos/services/memo_private_payload.dart';

final memoProvider =
    AsyncNotifierProvider<MemoNotifier, List<Map<String, dynamic>>>(
      MemoNotifier.new,
    );

class MemoNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  final _crypto = MemoCryptoService.instance;
  String? _query;
  String? _folderId;
  String? _tagId;
  bool _onlyArchived = false;
  MemoSortOption _sort = MemoSortOption.updatedDesc;
  int _requestRevision = 0;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    SyncService.addSyncCompletedListener(_onSyncCompleted);
    ref.onDispose(
      () => SyncService.removeSyncCompletedListener(_onSyncCompleted),
    );
    return _loadCurrentView();
  }

  Future<void> refresh({
    String? query,
    String? folderId,
    String? tagId,
    bool onlyArchived = false,
    MemoSortOption sort = MemoSortOption.updatedDesc,
  }) async {
    _query = query;
    _folderId = folderId;
    _tagId = tagId;
    _onlyArchived = onlyArchived;
    _sort = sort;
    await reloadCurrentView();
  }

  Future<void> reloadCurrentView() async {
    final revision = ++_requestRevision;
    try {
      final rows = await _loadCurrentView();
      if (revision == _requestRevision) state = AsyncData(rows);
    } catch (error, stackTrace) {
      reportDebugError('memo reload failed: $error\n$stackTrace');
      if (revision == _requestRevision) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<void> _onSyncCompleted() => reloadCurrentView();

  // ---------------------------------------------------------------------------
  // 锁状态查询（UI 直接使用）
  // ---------------------------------------------------------------------------

  /// 文件夹是否有锁。
  Future<bool> folderHasLock(String folderId) async =>
      (await MemoDatabase.getLockForFolder(folderId)) != null;

  /// 文件夹当前是否解锁（无锁 = 视为解锁）。
  Future<bool> isFolderUnlocked(String folderId) async {
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) return true;
    return _crypto.isFolderUnlocked(folderId);
  }

  /// 当前视图用到的所有锁（folderId -> lock 记录），供列表渲染锁图标。
  Future<Map<String, Map<String, dynamic>>> loadLocksByFolder() async {
    final locks = await MemoDatabase.getLocks();
    return {
      for (final lock in locks)
        if (lock['folderId'] is String && (lock['folderId'] as String).isNotEmpty)
          lock['folderId'] as String: lock,
    };
  }

  /// 默认锁（旧隐私密码迁移而来）是否存在。
  Future<bool> hasDefaultLock() => _crypto.hasDefaultLock;

  Future<List<Map<String, dynamic>>> _loadCurrentView() async {
    final query = _query;
    final rows = await MemoDatabase.getMemos(
      query: null,
      folderId: _folderId,
      tagId: _tagId,
      onlyArchived: _onlyArchived,
      sort: _sort,
    );
    final hydratedRows = _hydrateRows(rows);
    final needle = query?.trim().toLowerCase();
    if (needle == null || needle.isEmpty) return hydratedRows;
    // 有搜索词时在内存中过滤：已解锁的隐私内容参与匹配（标题/正文/标签），
    // 锁住的备忘录没有明文可搜，自然被排除。
    return hydratedRows.where((memo) {
      final title = memo['title'] as String? ?? '';
      final body = memo['bodyMd'] as String? ?? '';
      final tags = (memo['tagNames'] as List?)?.join(' ') ?? '';
      final searchable = '$title $body $tags'.toLowerCase();
      return searchable.contains(needle);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 备忘录 CRUD（锁感知）
  // ---------------------------------------------------------------------------

  /// 解析写入某文件夹的备忘录时应使用的加密密钥；文件夹没有锁时返回 null
  /// （普通明文备忘录）。
  Future<Uint8List?> _resolveFolderWriteKey(String? folderId) async {
    if (folderId == null) return null;
    final lock = await MemoDatabase.getLockForFolder(folderId);
    if (lock == null) return null;
    if (!_crypto.isFolderUnlocked(folderId)) {
      throw StateError('该文件夹已加密，请先解锁');
    }
    return _crypto.keyForMemoFolder(folderId);
  }

  Future<Map<String, dynamic>> create({
    String title = '未命名备忘录',
    String bodyMd = '',
    String? folderId,
    bool isPrivate = false,
    bool encryptTitle = false,
    bool aiAllowed = false,
  }) async {
    final folderKey = await _resolveFolderWriteKey(folderId);
    String? encryptedPayload;
    String? storedTitle = title;
    if (folderKey != null) {
      // 文件夹锁模式：整篇加密（标题并入密文），与旧 encryptTitle 语义无关。
      encryptedPayload = _crypto.encryptTextWithKey(
        encodeMemoPrivatePayload(title: title, bodyMd: bodyMd),
        folderKey,
      );
      storedTitle = '';
      isPrivate = true;
      encryptTitle = false;
    } else if (isPrivate) {
      if (!_crypto.isUnlocked) throw StateError('请先解锁隐私备忘录');
      encryptedPayload = _crypto.encryptText(
        encodeMemoPrivatePayload(title: title, bodyMd: bodyMd),
      );
    }
    final memo = await MemoDatabase.createMemo(
      title: storedTitle ?? '',
      bodyMd: bodyMd,
      folderId: isPrivate && encryptTitle ? null : folderId,
      isPrivate: isPrivate,
      encryptTitle: encryptTitle,
      encryptedPayload: encryptedPayload,
      aiAllowed: aiAllowed,
    );
    if (folderKey != null) {
      // 锁定文件夹内的备忘录不落任何明文标题。
      await MemoDatabase.updateMemo(memo['id'] as String, {
        'title': null,
        'bodyMd': null,
      });
    }
    await reloadCurrentView();
    return memo;
  }

  Future<void> updateMemo(
    String id, {
    String? title,
    String? bodyMd,
    bool? isPrivate,
    bool? encryptTitle,
    String? folderId,
    bool? pinned,
    bool? archived,
    bool? aiAllowed,
    bool snapshot = true,
    String snapshotSource = 'manual',
  }) async {
    final current = await MemoDatabase.getMemo(id);
    if (current == null) return;
    final currentFolderId = current['folderId'] as String?;
    // 编辑目标文件夹（若与当前不同）也需要解锁。
    final writeKey = await _resolveFolderWriteKey(
      folderId ?? currentFolderId,
    );
    final currentPrivatePayload = _decodePrivateMemo(current);
    final nextPrivate = writeKey != null ||
        (isPrivate ?? current['isPrivate'] == true);
    final nextEncryptTitle = writeKey == null &&
        (encryptTitle ?? current['encryptTitle'] == true);
    final updates = <String, dynamic>{
      if (folderId != null) 'folderId': folderId,
      if (pinned != null) 'pinned': pinned,
      if (archived != null) 'archived': archived,
      if (aiAllowed != null) 'aiAllowed': aiAllowed,
    };
    if (nextPrivate) {
      final nextTitle =
          title ??
          currentPrivatePayload?.title ??
          (current['title'] as String? ?? '未命名备忘录');
      final nextBody =
          bodyMd ??
          currentPrivatePayload?.bodyMd ??
          (current['bodyMd'] as String? ?? '');
      updates['isPrivate'] = true;
      updates['encryptTitle'] = nextEncryptTitle;
      updates['bodyMd'] = null;
      updates['encryptedPayload'] = writeKey != null
          ? _crypto.encryptTextWithKey(
              encodeMemoPrivatePayload(title: nextTitle, bodyMd: nextBody),
              writeKey,
            )
          : _crypto.encryptText(
              encodeMemoPrivatePayload(title: nextTitle, bodyMd: nextBody),
            );
      updates['title'] = nextEncryptTitle || writeKey != null ? null : nextTitle;
    } else {
      if (title != null) updates['title'] = title;
      if (bodyMd != null) updates['bodyMd'] = bodyMd;
    }
    // 自动保存不生成版本快照，避免高频保存挤掉用户有意义的版本历史；
    // 手动保存和恢复历史前仍会先保存当前版本。
    if (snapshot) {
      await MemoDatabase.createVersion(
        id,
        title: current['title'] as String?,
        bodyMd: current['bodyMd'] as String?,
        encryptedPayload: current['encryptedPayload'] as String?,
        isPrivate: current['isPrivate'] == true,
        pinned: current['pinned'] == true,
        source: snapshotSource,
      );
    }
    await MemoDatabase.updateMemo(id, updates);
    await reloadCurrentView();
  }

  /// 移动备忘录：来源/目标任一是加密文件夹都必须先解锁；
  /// 跨加密区域移动时用目标锁的密钥重加密（密文不落地）。
  Future<void> moveMemo(String id, String? targetFolderId) async {
    final current = await MemoDatabase.getMemo(id);
    if (current == null) throw StateError('备忘录不存在或已删除');
    final sourceFolderId = current['folderId'] as String?;
    if (sourceFolderId != null) {
      final sourceLock = await MemoDatabase.getLockForFolder(sourceFolderId);
      if (sourceLock != null && !_crypto.isFolderUnlocked(sourceFolderId)) {
        throw StateError('请先解锁原文件夹后再移动');
      }
    }
    if (targetFolderId != null) {
      final targetLock = await MemoDatabase.getLockForFolder(targetFolderId);
      if (targetLock != null && !_crypto.isFolderUnlocked(targetFolderId)) {
        throw StateError('请先解锁目标文件夹');
      }
      final targetRows = await MemoDatabase.getAllFolders();
      final targets = targetRows.where((f) => f['id'] == targetFolderId).toList();
      if (targets.isNotEmpty && targets.first['archived'] == true) {
        throw StateError('目标文件夹已归档');
      }
    }
    await MemoDatabase.moveMemo(id, targetFolderId);
    // 重新加密/解密转换。
    final sourceKey = _crypto.keyForMemoFolder(sourceFolderId);
    final targetKey = await _resolveFolderWriteKey(targetFolderId);
    final sourcePayload = current['encryptedPayload'] as String?;
    if (targetKey != null) {
      // 进入（或在两个）加密文件夹：统一用目标密钥整篇加密。
      final payloadText = sourceKey != null && sourcePayload != null
          ? _crypto.decryptTextWithKey(sourcePayload, sourceKey)
          : encodeMemoPrivatePayload(
              title: current['title'] as String? ?? '未命名备忘录',
              bodyMd: current['bodyMd'] as String? ?? '',
            );
      await MemoDatabase.updateMemo(id, {
        'isPrivate': true,
        'encryptTitle': false,
        'encryptedPayload': _crypto.encryptTextWithKey(payloadText, targetKey),
        'title': null,
        'bodyMd': null,
      });
    } else if (sourceKey != null &&
        current['isPrivate'] == true &&
        sourcePayload != null) {
      // 移出加密文件夹：解密转普通备忘录（OneNote 语义）。
      final payloadText = _crypto.decryptTextWithKey(sourcePayload, sourceKey);
      final payload = decodeMemoPrivatePayload(payloadText);
      await MemoDatabase.updateMemo(id, {
        'isPrivate': false,
        'encryptTitle': false,
        'encryptedPayload': null,
        'title': payload.title,
        'bodyMd': payload.bodyMd,
      });
    }
    await reloadCurrentView();
  }

  // ---------------------------------------------------------------------------
  // 文件夹锁管理（UI 调用）
  // ---------------------------------------------------------------------------

  Future<String> setupFolderLock(String folderId, String password) async {
    final recoveryKey = await _crypto.setupFolderLock(folderId, password);
    // OneNote 语义：给分区上锁会立即加密其中所有页面。文件夹里已存在的
    // 普通备忘录就地整篇加密（标题并入密文），不留任何明文。
    final memos = await MemoDatabase.getMemos(folderId: folderId);
    final key = _crypto.keyForMemoFolder(folderId);
    if (key != null) {
      for (final memo in memos) {
        if (memo['isPrivate'] == true) continue;
        final payloadText = encodeMemoPrivatePayload(
          title: memo['title'] as String? ?? '未命名备忘录',
          bodyMd: memo['bodyMd'] as String? ?? '',
        );
        await MemoDatabase.updateMemo(memo['id'] as String, {
          'isPrivate': true,
          'encryptTitle': false,
          'encryptedPayload': _crypto.encryptTextWithKey(payloadText, key),
          'title': null,
          'bodyMd': null,
        });
      }
    }
    await reloadCurrentView();
    return recoveryKey;
  }

  Future<bool> unlockFolderWithPassword(String folderId, String password) async {
    final ok = await _crypto.unlockFolderWithPassword(folderId, password);
    if (ok) await reloadCurrentView();
    return ok;
  }

  Future<bool> unlockFolderWithRecoveryKey(
    String folderId,
    String recoveryKey,
  ) async {
    final ok = await _crypto.unlockFolderWithRecoveryKey(folderId, recoveryKey);
    if (ok) await reloadCurrentView();
    return ok;
  }

  Future<bool> unlockFolderWithEscrow(String folderId) async {
    final ok = await MemoEscrowService.unlockFolder(folderId);
    if (ok) await reloadCurrentView();
    return ok;
  }

  Future<void> lockFolder(String folderId) async {
    _crypto.lockFolder(folderId);
    await reloadCurrentView();
  }

  Future<void> lockAll() async {
    _crypto.lockAll();
    await reloadCurrentView();
  }

  Future<void> changeFolderLockPassword(
    String folderId,
    String newPassword,
  ) async {
    await _crypto.changeFolderLockPassword(folderId, newPassword);
    await reloadCurrentView();
  }

  Future<String> rotateRecoveryKey(String folderId) async {
    final key = await _crypto.rotateRecoveryKey(folderId);
    await reloadCurrentView();
    return key;
  }

  Future<int> removeFolderLock(String folderId) async {
    final converted = await _crypto.removeFolderLock(folderId);
    await reloadCurrentView();
    return converted;
  }

  Future<void> enableEscrow(String folderId) async {
    await MemoEscrowService.enableForFolder(folderId);
    await reloadCurrentView();
  }

  Future<void> disableEscrow(String folderId) async {
    await _crypto.disableEscrow(folderId);
    await reloadCurrentView();
  }

  // ---------------------------------------------------------------------------
  // 文件夹管理
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> loadTrash() => MemoDatabase.getMemos(
    includeDeleted: true,
    includeArchived: true,
  ).then((rows) => rows.where((m) => m['deleted'] == true).toList());

  Future<void> restore(String id) async {
    await MemoDatabase.restoreMemo(id);
    await reloadCurrentView();
  }

  Future<void> unarchive(String id) async {
    await MemoDatabase.updateMemo(id, {'archived': false});
    await reloadCurrentView();
  }

  /// 从回收站物理删除备忘录及其版本历史和标签关系。
  Future<void> purge(String id) async {
    await MemoDatabase.purgeMemo(id);
    await reloadCurrentView();
  }

  Future<void> setTags(String memoId, List<String> tagIds) async {
    await MemoDatabase.setMemoTags(memoId, tagIds);
    await reloadCurrentView();
  }

  Future<Map<String, dynamic>> createTag(String name) =>
      MemoDatabase.createTag(name);

  Future<List<Map<String, dynamic>>> loadTags() => MemoDatabase.getTags();

  Future<List<Map<String, dynamic>>> loadFolders() =>
      MemoDatabase.getAllFolders();

  Future<Map<String, dynamic>> createFolder(String name, {String? parentId}) =>
      MemoDatabase.createFolder(name, parentId: parentId);

  Future<void> renameFolder(String id, String name) =>
      MemoDatabase.updateFolder(id, name: name);

  /// 仅软删除文件夹本身；其中的备忘录保留，之后在“全部备忘录”可见。
  Future<void> deleteFolder(String id) async {
    await MemoDatabase.deleteFolder(id);
    _crypto.lockFolder(id);
    await reloadCurrentView();
  }

  Future<List<Map<String, dynamic>>> loadVersions(String memoId) =>
      MemoDatabase.getVersions(memoId);

  _PrivateMemo? _decodePrivateMemo(Map<String, dynamic> memo) {
    if (memo['isPrivate'] != true) return null;
    final key = _crypto.keyForMemoFolder(memo['folderId'] as String?);
    if (key == null) return null;
    final encrypted = memo['encryptedPayload'] as String?;
    if (encrypted == null || encrypted.isEmpty) return null;
    try {
      final decoded = decodeMemoPrivatePayload(
        _crypto.decryptTextWithKey(encrypted, key),
      );
      return _PrivateMemo(decoded.title, decoded.bodyMd);
    } catch (_) {
      return null;
    }
  }

  /// 用各备忘录对应的锁密钥水合明文；解不开的标记为 locked 并清空明文。
  List<Map<String, dynamic>> _hydrateRows(List<Map<String, dynamic>> rows) {
    return rows.map((memo) {
      if (memo['isPrivate'] != true) return memo;
      final key = _crypto.keyForMemoFolder(memo['folderId'] as String?);
      final encrypted = memo['encryptedPayload'] as String?;
      if (key == null || encrypted == null || encrypted.isEmpty) {
        return _asLockedRow(memo);
      }
      try {
        final decoded = decodeMemoPrivatePayload(
          _crypto.decryptTextWithKey(encrypted, key),
        );
        final hydrated = Map<String, dynamic>.from(memo)
          ..['title'] = decoded.title
          ..['bodyMd'] = decoded.bodyMd
          ..['locked'] = false;
        // 兼容旧 encryptTitle 语义：标题加密的存量备忘录不泄露分类元数据。
        if (memo['encryptTitle'] == true) {
          hydrated['folderName'] = null;
          hydrated['tagNames'] = const <String>[];
        }
        return hydrated;
      } catch (_) {
        return _asLockedRow(memo);
      }
    }).toList();
  }

  Map<String, dynamic> _asLockedRow(Map<String, dynamic> memo) {
    return Map<String, dynamic>.from(memo)
      ..['title'] = null
      ..['bodyMd'] = null
      ..['locked'] = true
      // 锁住的备忘录隐藏全部元数据（OneNote：分区上锁后页面标题不可见）。
      ..['folderName'] = null
      ..['tagNames'] = const <String>[];
  }
}

class _PrivateMemo {
  const _PrivateMemo(this.title, this.bodyMd);

  final String title;
  final String bodyMd;
}
