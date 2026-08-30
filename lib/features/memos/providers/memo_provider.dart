import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';

final memoProvider =
    AsyncNotifierProvider<MemoNotifier, List<Map<String, dynamic>>>(
      MemoNotifier.new,
    );

class MemoNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  final _crypto = MemoCryptoService.instance;

  @override
  Future<List<Map<String, dynamic>>> build() => MemoDatabase.getMemos();

  Future<void> refresh({String? query, String? folderId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final hasPrivateSearch =
          query != null && query.trim().isNotEmpty && _crypto.isUnlocked;
      final rows = await MemoDatabase.getMemos(
        query: hasPrivateSearch ? null : query,
        folderId: folderId,
      );
      if (!hasPrivateSearch) return rows;
      final needle = query.trim().toLowerCase();
      return rows.where((memo) {
        final title = memo['title'] as String? ?? '';
        final body = memo['bodyMd'] as String? ?? '';
        final privateMemo = _decodePrivateMemo(memo);
        final searchable =
            '$title $body '
                    '${privateMemo?.title ?? ''} ${privateMemo?.bodyMd ?? ''}'
                .toLowerCase();
        return searchable.contains(needle);
      }).toList();
    });
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
        _encodePrivatePayload(title: title, bodyMd: bodyMd),
      );
    }
    final memo = await MemoDatabase.createMemo(
      title: title,
      bodyMd: bodyMd,
      folderId: folderId,
      isPrivate: isPrivate,
      encryptTitle: encryptTitle,
      encryptedPayload: encryptedPayload,
      aiAllowed: aiAllowed,
    );
    await refresh();
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
        _encodePrivatePayload(title: nextTitle, bodyMd: nextBody),
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
    await refresh();
  }

  Future<List<Map<String, dynamic>>> loadTrash() => MemoDatabase.getMemos(
    includeDeleted: true,
    includeArchived: true,
  ).then((rows) => rows.where((m) => m['deleted'] == true).toList());

  Future<void> restore(String id) async {
    await MemoDatabase.restoreMemo(id);
    await refresh();
  }

  /// 从回收站物理删除备忘录及其版本历史和标签关系。
  Future<void> purge(String id) async {
    await MemoDatabase.purgeMemo(id);
    await refresh();
  }

  Future<void> setTags(String memoId, List<String> tagIds) async {
    await MemoDatabase.setMemoTags(memoId, tagIds);
    await refresh();
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
    await refresh();
  }

  Future<List<Map<String, dynamic>>> loadVersions(String memoId) =>
      MemoDatabase.getVersions(memoId);

  static String _encodePrivatePayload({
    required String title,
    required String bodyMd,
  }) => '$title\n\u0000$bodyMd';

  _PrivateMemo? _decodePrivateMemo(Map<String, dynamic> memo) {
    if (memo['isPrivate'] != true || !_crypto.isUnlocked) return null;
    final encrypted = memo['encryptedPayload'] as String?;
    if (encrypted == null || encrypted.isEmpty) return null;
    try {
      final decoded = _crypto.decryptText(encrypted);
      final separator = decoded.indexOf('\u0000');
      if (separator < 0) return _PrivateMemo(decoded, '');
      return _PrivateMemo(
        decoded.substring(0, separator),
        decoded.substring(separator + 1),
      );
    } catch (_) {
      return null;
    }
  }
}

class _PrivateMemo {
  const _PrivateMemo(this.title, this.bodyMd);

  final String title;
  final String bodyMd;
}
