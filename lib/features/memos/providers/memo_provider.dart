import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
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
      if (revision == _requestRevision) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<void> _onSyncCompleted() => reloadCurrentView();

  Future<List<Map<String, dynamic>>> _loadCurrentView() async {
    final query = _query;
    final hasPrivateSearch =
        query != null && query.trim().isNotEmpty && _crypto.isUnlocked;
    final rows = await MemoDatabase.getMemos(
      query: hasPrivateSearch ? null : query,
      folderId: _folderId,
      tagId: _tagId,
      onlyArchived: _onlyArchived,
      sort: _sort,
    );
    final hydratedRows = _hydratePrivateRows(rows);
    if (!hasPrivateSearch) return hydratedRows;
    final needle = query.trim().toLowerCase();
    return hydratedRows.where((memo) {
      final title = memo['title'] as String? ?? '';
      final body = memo['bodyMd'] as String? ?? '';
      final tags = (memo['tagNames'] as List?)?.join(' ') ?? '';
      final searchable = '$title $body $tags'.toLowerCase();
      return searchable.contains(needle);
    }).toList();
  }

  Future<Map<String, dynamic>> create({
    String title = '未命名备忘录',
    String bodyMd = '',
    String? folderId,
    bool isPrivate = false,
    bool encryptTitle = false,
    bool aiAllowed = false,
  }) async {
    String? encryptedPayload;
    if (isPrivate) {
      if (!_crypto.isUnlocked) throw StateError('请先解锁隐私保险库');
      encryptedPayload = _crypto.encryptText(
        encodeMemoPrivatePayload(title: title, bodyMd: bodyMd),
      );
    }
    final memo = await MemoDatabase.createMemo(
      title: title,
      bodyMd: bodyMd,
      folderId: isPrivate && encryptTitle ? null : folderId,
      isPrivate: isPrivate,
      encryptTitle: encryptTitle,
      encryptedPayload: encryptedPayload,
      aiAllowed: aiAllowed,
    );
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
    final nextPrivate = isPrivate ?? current['isPrivate'] == true;
    final currentPrivatePayload = _decodePrivateMemo(current);
    final updates = <String, dynamic>{
      if (folderId != null) 'folderId': folderId,
      if (title != null &&
          !(nextPrivate && (encryptTitle ?? current['encryptTitle'] == true)))
        'title': title,
      if (bodyMd != null && !nextPrivate) 'bodyMd': bodyMd,
      if (isPrivate != null) 'isPrivate': isPrivate,
      if (encryptTitle != null) 'encryptTitle': encryptTitle,
      if (pinned != null) 'pinned': pinned,
      if (archived != null) 'archived': archived,
      if (aiAllowed != null) 'aiAllowed': aiAllowed,
    };
    if (nextPrivate) {
      if (!_crypto.isUnlocked) throw StateError('请先解锁隐私保险库');
      final nextTitle =
          title ??
          currentPrivatePayload?.title ??
          (current['title'] as String? ?? '未命名备忘录');
      final nextBody =
          bodyMd ??
          currentPrivatePayload?.bodyMd ??
          (current['bodyMd'] as String? ?? '');
      updates['encryptedPayload'] = _crypto.encryptText(
        encodeMemoPrivatePayload(title: nextTitle, bodyMd: nextBody),
      );
      updates['title'] = (encryptTitle ?? current['encryptTitle'] == true)
          ? null
          : nextTitle;
      updates['bodyMd'] = null;
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
    await reloadCurrentView();
  }

  Future<List<Map<String, dynamic>>> loadVersions(String memoId) =>
      MemoDatabase.getVersions(memoId);

  _PrivateMemo? _decodePrivateMemo(Map<String, dynamic> memo) {
    if (memo['isPrivate'] != true || !_crypto.isUnlocked) return null;
    final encrypted = memo['encryptedPayload'] as String?;
    if (encrypted == null || encrypted.isEmpty) return null;
    try {
      final decoded = decodeMemoPrivatePayload(_crypto.decryptText(encrypted));
      return _PrivateMemo(decoded.title, decoded.bodyMd);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _hydratePrivateRows(
    List<Map<String, dynamic>> rows,
  ) {
    if (!_crypto.isUnlocked) return rows;
    return rows.map((memo) {
      final privateMemo = _decodePrivateMemo(memo);
      if (privateMemo == null) return memo;
      final hydrated = Map<String, dynamic>.from(memo)
        ..['title'] = privateMemo.title
        ..['bodyMd'] = privateMemo.bodyMd;
      if (memo['encryptTitle'] == true) {
        hydrated['folderName'] = null;
        hydrated['tagNames'] = const <String>[];
      }
      return hydrated;
    }).toList();
  }
}

class _PrivateMemo {
  const _PrivateMemo(this.title, this.bodyMd);

  final String title;
  final String bodyMd;
}
