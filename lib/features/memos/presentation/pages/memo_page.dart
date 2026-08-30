import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/memos/providers/memo_provider.dart';
import 'package:focus_my_time/features/memos/services/memo_attachment_service.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/services/memo_draft_service.dart';
import 'package:focus_my_time/features/memos/services/memo_image_service.dart';
import 'package:focus_my_time/features/memos/presentation/widgets/markdown_preview.dart';

class MemoPage extends ConsumerStatefulWidget {
  const MemoPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends ConsumerState<MemoPage> {
  final _searchController = TextEditingController();
  String? _selectedId;
  bool _preview = true;
  bool _showTrash = false;
  bool _searchVisible = false;
  String? _selectedFolderId;
  List<Map<String, dynamic>> _folders = const [];
  List<Map<String, dynamic>>? _trashItems;

  static const _manageFoldersAction = '__manage_folders__';

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final folders = await ref.read(memoProvider.notifier).loadFolders();
    if (!mounted) return;
    setState(() => _folders = folders);
  }

  void _applyMemoFilter() {
    ref
        .read(memoProvider.notifier)
        .refresh(query: _searchController.text, folderId: _selectedFolderId);
  }

  int _folderDepth(String? folderId) {
    var depth = 0;
    var current = folderId;
    while (current != null) {
      final parent =
          _folders.where((f) => f['id'] == current).firstOrNull?['parentId']
              as String?;
      if (parent == null || depth > 20) break;
      current = parent;
      depth++;
    }
    return depth;
  }

  String get _currentFolderName {
    if (_selectedFolderId == null) return '全部备忘录';
    for (final folder in _folders) {
      if (folder['id'] == _selectedFolderId) {
        return folder['name'] as String? ?? '未命名文件夹';
      }
    }
    return '已删除的文件夹';
  }

  @override
  Widget build(BuildContext context) {
    final memos = ref.watch(memoProvider);
    final crypto = MemoCryptoService.instance;
    final isMobile = MediaQuery.sizeOf(context).width < 800;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text('备忘录', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: _searchVisible ? '收起搜索' : '搜索备忘录',
                onPressed: () {
                  setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) {
                      _searchController.clear();
                      _applyMemoFilter();
                    }
                  });
                },
                icon: Icon(_searchVisible ? Icons.search_off : Icons.search),
              ),
              IconButton(
                tooltip: crypto.isUnlocked ? '锁定隐私内容' : '解锁隐私内容',
                onPressed: () => _toggleVault(),
                icon: Icon(crypto.isUnlocked ? AppIcons.unlock : AppIcons.lock),
              ),
              IconButton(
                tooltip: _showTrash ? '返回备忘录列表' : '回收站',
                onPressed: () => setState(() {
                  _showTrash = !_showTrash;
                  if (_showTrash) _loadTrash();
                }),
                icon: Icon(
                  _showTrash ? Icons.arrow_back : Icons.delete_outline,
                ),
              ),
              IconButton(
                tooltip: '新建备忘录',
                onPressed: () => _createMemo(context),
                icon: const Icon(AppIcons.add),
              ),
              IconButton(
                tooltip: '返回任务界面',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (!_showTrash) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                _buildFolderSelector(),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '新建文件夹',
                  onPressed: () => _showCreateFolderDialog(),
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
          ),
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => _applyMemoFilter(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '搜索备忘录（解锁后可搜索隐私内容）',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: '收起搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _searchVisible = false;
                        _searchController.clear();
                      });
                      _applyMemoFilter();
                    },
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: memos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('加载失败：$error')),
            data: (items) => _showTrash
                ? _buildTrashList(_trashItems ?? const [])
                : isMobile
                ? _buildMobileMemoPane(items)
                : Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _buildMemoTile(items[index]),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _selectedId == null
                            ? const Center(child: Text('选择一篇备忘录开始编辑'))
                            : _MemoEditor(
                                key: ValueKey(_selectedId),
                                memoId: _selectedId!,
                                preview: _preview,
                                onPreviewChanged: (value) =>
                                    setState(() => _preview = value),
                                onTrash: () {
                                  setState(() => _selectedId = null);
                                  ref.read(memoProvider.notifier).refresh();
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderSelector() {
    return PopupMenuButton<String>(
      tooltip: '选择文件夹',
      onSelected: (value) {
        if (value == _manageFoldersAction) {
          _showManageFoldersDialog();
          return;
        }
        setState(() => _selectedFolderId = value.isEmpty ? null : value);
        _applyMemoFilter();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: '',
          child: Row(
            children: [
              Icon(Icons.notes, size: 18),
              SizedBox(width: 8),
              Text('全部备忘录'),
            ],
          ),
        ),
        for (final folder in _folders)
          PopupMenuItem(
            value: folder['id'] as String,
            child: Text(
              '${'　' * _folderDepth(folder['parentId'] as String?)}${folder['name'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _manageFoldersAction,
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 18),
              SizedBox(width: 8),
              Text('管理文件夹'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: context.appColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_outlined, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                _currentFolderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final nameController = TextEditingController();
    String? parentId;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建文件夹'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  onSubmitted: (value) => Navigator.of(dialogContext).pop(true),
                  decoration: const InputDecoration(labelText: '文件夹名称'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: parentId,
                  decoration: const InputDecoration(labelText: '上级文件夹'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不放入文件夹')),
                    for (final folder in _folders)
                      DropdownMenuItem(
                        value: folder['id'] as String,
                        child: Text(
                          '${'　' * _folderDepth(folder['parentId'] as String?)}${folder['name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => parentId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    try {
      final folder = await ref
          .read(memoProvider.notifier)
          .createFolder(name, parentId: parentId);
      await _loadFolders();
      if (!mounted) return;
      setState(() => _selectedFolderId = folder['id'] as String);
      _applyMemoFilter();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件夹创建失败：$error')));
    }
  }

  Future<void> _showManageFoldersDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('管理文件夹'),
          content: SizedBox(
            width: 380,
            height: 380,
            child: _folders.isEmpty
                ? const Center(child: Text('还没有文件夹'))
                : ListView.builder(
                    itemCount: _folders.length,
                    itemBuilder: (context, index) {
                      final folder = _folders[index];
                      final depth = _folderDepth(folder['parentId'] as String?);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Padding(
                          padding: EdgeInsets.only(left: depth * 16.0),
                          child: Text(
                            folder['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        leading: const Icon(Icons.folder_outlined, size: 18),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            final id = folder['id'] as String;
                            final name = folder['name'] as String? ?? '';
                            if (action == 'rename') {
                              final newName = await _askText(
                                dialogContext,
                                '重命名文件夹',
                                '文件夹名称',
                                initialText: name,
                              );
                              if (newName == null || newName.trim().isEmpty) {
                                return;
                              }
                              try {
                                await ref
                                    .read(memoProvider.notifier)
                                    .renameFolder(id, newName.trim());
                              } catch (error) {
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    SnackBar(content: Text('重命名失败：$error')),
                                  );
                                }
                                return;
                              }
                            } else if (action == 'delete') {
                              final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('删除文件夹'),
                                  content: Text(
                                    '将删除文件夹“$name”。其中的备忘录会保留，之后可在“全部备忘录”中查看。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              await ref
                                  .read(memoProvider.notifier)
                                  .deleteFolder(id);
                              if (mounted && _selectedFolderId == id) {
                                setState(() => _selectedFolderId = null);
                                _applyMemoFilter();
                              }
                            }
                            final folders = await ref
                                .read(memoProvider.notifier)
                                .loadFolders();
                            setDialogState(() => _folders = folders);
                            if (mounted) setState(() => _folders = folders);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _showCreateFolderDialog();
              },
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('新建文件夹'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 移动端单栏导航：未选中时全屏列表，选中后全屏编辑器。
  Widget _buildMobileMemoPane(List<Map<String, dynamic>> items) {
    if (_selectedId == null) {
      if (items.isEmpty) {
        return const Center(child: Text('还没有备忘录，点右上角 + 新建'));
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _buildMemoTile(items[index]),
      );
    }
    return _MemoEditor(
      key: ValueKey(_selectedId),
      memoId: _selectedId!,
      preview: _preview,
      isMobile: true,
      onBack: () => setState(() => _selectedId = null),
      onPreviewChanged: (value) => setState(() => _preview = value),
      onTrash: () {
        setState(() => _selectedId = null);
        ref.read(memoProvider.notifier).refresh();
      },
    );
  }

  Widget _buildMemoTile(Map<String, dynamic> memo) {
    final crypto = MemoCryptoService.instance;
    final id = memo['id'] as String;
    final isPrivate = memo['isPrivate'] == true;
    final encryptedTitle = memo['encryptTitle'] == true;
    final locked = isPrivate && !crypto.isUnlocked;
    final title = locked && encryptedTitle
        ? '隐私备忘录'
        : (memo['title'] as String? ?? '未命名备忘录');
    final pinned = memo['pinned'] == true;
    return ListTile(
      selected: _selectedId == id,
      leading: Icon(isPrivate ? AppIcons.lock : AppIcons.memo, size: 20),
      title: Row(
        children: [
          if (pinned) ...[
            Icon(
              Icons.push_pin,
              size: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(_formatDate(memo['updatedAt'] as int?), maxLines: 1),
      onTap: () => setState(() => _selectedId = id),
    );
  }

  Widget _buildTrashList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(child: Text('回收站是空的'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final memo = items[index];
        return ListTile(
          leading: const Icon(Icons.delete_outline, size: 20),
          title: Text(
            memo['title'] as String? ?? '未命名备忘录',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('删除于 ${_formatDate(memo['updatedAt'] as int?)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '恢复',
                icon: const Icon(Icons.restore),
                onPressed: () async {
                  await ref
                      .read(memoProvider.notifier)
                      .restore(memo['id'] as String);
                  await _loadTrash();
                },
              ),
              IconButton(
                tooltip: '彻底删除',
                icon: const Icon(Icons.delete_forever),
                onPressed: () => _confirmPurge(memo),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadTrash() async {
    final items = await ref.read(memoProvider.notifier).loadTrash();
    if (mounted) setState(() => _trashItems = items);
  }

  Future<void> _confirmPurge(Map<String, dynamic> memo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('彻底删除'),
        content: const Text('将物理删除这篇备忘录及其全部版本历史，此操作无法撤销。附件记录保留，可在容量管理中清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(memoProvider.notifier).purge(memo['id'] as String);
    await _loadTrash();
  }

  Future<void> _toggleVault() async {
    final crypto = MemoCryptoService.instance;
    if (crypto.isUnlocked) {
      crypto.lock();
      setState(() {});
      return;
    }
    final password = await _askPassword(context, '解锁隐私备忘录');
    if (password == null) return;
    final ok = await crypto.unlockWithPassword(password);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('隐私密码不正确')));
      return;
    }
    setState(() {});
    ref.invalidate(memoProvider);
    _applyMemoFilter();
    // 解锁后立即清理上传队列中的私密附件。
    try {
      final failure = await MemoImageService.instance.flushUploadQueue();
      if (!mounted) return;
      if (failure != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('部分附件上传失败：\n$failure')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('附件上传队列处理失败：$error')));
      }
    }
  }

  Future<void> _createMemo(BuildContext context) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    var isPrivate = false;
    var encryptTitle = false;
    var aiAllowed = false;
    String? folderId;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建备忘录'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Markdown 内容'),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: ref.read(memoProvider.notifier).loadFolders(),
                  builder: (context, snapshot) {
                    final folders = snapshot.data ?? const [];
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: folderId,
                            decoration: const InputDecoration(
                              labelText: '所属文件夹',
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('不放入文件夹'),
                              ),
                              for (final folder in folders)
                                DropdownMenuItem(
                                  value: folder['id'] as String,
                                  child: Text(folder['name'] as String? ?? ''),
                                ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => folderId = value),
                          ),
                        ),
                        IconButton(
                          tooltip: '新建文件夹',
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: () async {
                            final name = await _askText(
                              dialogContext,
                              '新建文件夹',
                              '文件夹名称',
                            );
                            if (name == null || name.trim().isEmpty) return;
                            try {
                              final folder = await ref
                                  .read(memoProvider.notifier)
                                  .createFolder(name.trim());
                              setDialogState(
                                () => folderId = folder['id'] as String,
                              );
                            } catch (error) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  SnackBar(content: Text('文件夹创建失败：$error')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPrivate,
                  onChanged: (value) => setDialogState(() {
                    isPrivate = value == true;
                    if (!isPrivate) encryptTitle = false;
                  }),
                  title: const Text('设为隐私备忘录'),
                ),
                if (isPrivate)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: encryptTitle,
                    onChanged: (value) =>
                        setDialogState(() => encryptTitle = value == true),
                    title: const Text('同时加密标题（隐藏文件夹和标签关系）'),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: aiAllowed,
                  onChanged: (value) =>
                      setDialogState(() => aiAllowed = value == true),
                  title: const Text('允许 AI 助手读取本篇内容'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final memo = await ref
                      .read(memoProvider.notifier)
                      .create(
                        title: titleController.text.trim().isEmpty
                            ? '未命名备忘录'
                            : titleController.text.trim(),
                        bodyMd: bodyController.text,
                        folderId: folderId,
                        isPrivate: isPrivate,
                        encryptTitle: encryptTitle,
                        aiAllowed: aiAllowed,
                      );
                  setState(() => _selectedId = memo['id'] as String);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    bodyController.dispose();
    if (created == true && mounted) setState(() {});
  }

  Future<String?> _askText(
    BuildContext dialogContext,
    String title,
    String label, {
    String? initialText,
  }) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<String?> _askPassword(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(labelText: '隐私密码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  static String _formatDate(int? timestamp) => formatMemoDate(timestamp);
}

String formatMemoDate(int? timestamp) {
  if (timestamp == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _MemoEditor extends ConsumerStatefulWidget {
  const _MemoEditor({
    super.key,
    required this.memoId,
    required this.preview,
    required this.onPreviewChanged,
    required this.onTrash,
    this.isMobile = false,
    this.onBack,
  });

  final String memoId;
  final bool preview;
  final ValueChanged<bool> onPreviewChanged;
  final VoidCallback onTrash;
  final bool isMobile;
  final VoidCallback? onBack;

  @override
  ConsumerState<_MemoEditor> createState() => _MemoEditorState();
}

class _MemoEditorState extends ConsumerState<_MemoEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _editorScrollController = ScrollController();
  final _previewScrollController = ScrollController();
  final _previewText = ValueNotifier<String>('');
  Timer? _previewDebounce;
  Timer? _autoSaveTimer;
  Timer? _draftTimer;
  String? _savedTitle;
  String? _savedBody;
  _AutoSaveStatus _autoSaveStatus = _AutoSaveStatus.none;
  DateTime? _lastSavedAt;
  DateTime? _lastAutoVersionAt;
  bool _syncingScroll = false;
  bool _loaded = false;
  bool _saving = false;
  bool _draftChecked = false;
  bool _autoSaveEnabled = true;
  int _autoSaveDelayMs = 2500;

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_onContentChanged);
    _titleController.addListener(_onTitleChanged);
    _loadAutoSaveSettings();
    _editorScrollController.addListener(() => _syncScroll(fromEditor: true));
    _previewScrollController.addListener(() => _syncScroll(fromEditor: false));
  }

  void _onContentChanged() {
    _schedulePreviewUpdate();
    _scheduleAutoSave();
    _scheduleDraftWrite();
  }

  void _onTitleChanged() {
    _scheduleAutoSave();
    _scheduleDraftWrite();
  }

  bool get _isDirty =>
      _titleController.text != (_savedTitle ?? '') ||
      _bodyController.text != (_savedBody ?? '');

  /// 停止输入后自动保存；自动版本至少间隔 5 分钟，避免高频输入占满历史。
  void _scheduleAutoSave() {
    if (!_autoSaveEnabled || !_isDirty) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(Duration(milliseconds: _autoSaveDelayMs), () {
      final now = DateTime.now();
      final snapshot =
          _lastAutoVersionAt == null ||
          now.difference(_lastAutoVersionAt!) >= const Duration(minutes: 5);
      _performSave(snapshot: snapshot, manual: false, source: 'auto');
      if (snapshot) _lastAutoVersionAt = now;
    });
  }

  void _scheduleDraftWrite() {
    if (!_loaded || !_isDirty) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), () {
      try {
        final memo = ref
            .read(memoProvider)
            .valueOrNull
            ?.where((item) => item['id'] == widget.memoId)
            .firstOrNull;
        final isPrivate = memo?['isPrivate'] == true;
        final data = isPrivate
            ? {
                'private': true,
                'payload': MemoCryptoService.instance.encryptText(
                  '${_titleController.text}\u0000${_bodyController.text}',
                ),
              }
            : {
                'private': false,
                'title': _titleController.text,
                'body': _bodyController.text,
              };
        writeMemoDraft(widget.memoId, jsonEncode(data));
      } catch (_) {
        // 草稿只是意外退出兜底，写入失败不影响正常编辑与数据库保存。
      }
    });
  }

  Future<void> _checkDraft(bool isPrivate) async {
    if (_draftChecked) return;
    _draftChecked = true;
    try {
      final raw = readMemoDraft(widget.memoId);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      String title;
      String body;
      if (data['private'] == true) {
        if (!isPrivate) {
          clearMemoDraft(widget.memoId);
          return;
        }
        final decoded = MemoCryptoService.instance.decryptText(
          data['payload'] as String,
        );
        final separator = decoded.indexOf('\u0000');
        title = separator < 0 ? '' : decoded.substring(0, separator);
        body = separator < 0 ? decoded : decoded.substring(separator + 1);
      } else {
        title = data['title'] as String? ?? '';
        body = data['body'] as String? ?? '';
      }
      if (title == _savedTitle && body == _savedBody) {
        clearMemoDraft(widget.memoId);
        return;
      }
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('检测到未保存的草稿'),
          content: const Text('上次编辑可能未正常保存，是否恢复草稿？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('丢弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (restore == true) {
        _titleController.text = title;
        _bodyController.text = body;
        _previewText.value = body;
        _scheduleAutoSave();
      } else {
        clearMemoDraft(widget.memoId);
      }
    } catch (error) {
      clearMemoDraft(widget.memoId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('草稿恢复失败：$error')));
      }
    }
  }

  Future<void> _loadAutoSaveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _autoSaveEnabled = prefs.getBool('memo_auto_save_enabled') ?? true;
        _autoSaveDelayMs = prefs.getInt('memo_auto_save_delay_ms') ?? 2500;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取自动保存设置失败：$error')));
      }
    }
  }

  Future<void> _showAutoSaveSettings() async {
    var enabled = _autoSaveEnabled;
    var delay = _autoSaveDelayMs;
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自动保存设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用自动保存'),
                value: enabled,
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
              DropdownButtonFormField<int>(
                initialValue: delay,
                decoration: const InputDecoration(labelText: '保存延迟'),
                items: const [1000, 2500, 5000, 10000]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('${value / 1000} 秒'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => delay = value ?? 2500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (enabled, delay)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('memo_auto_save_enabled', result.$1);
      await prefs.setInt('memo_auto_save_delay_ms', result.$2);
      if (!mounted) return;
      setState(() {
        _autoSaveEnabled = result.$1;
        _autoSaveDelayMs = result.$2;
      });
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存自动保存设置失败：$error')));
    }
  }

  Future<void> _performSave({
    required bool snapshot,
    required bool manual,
    String source = 'manual',
  }) async {
    if (_saving || !_isDirty) {
      if (manual && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有需要保存的修改')));
      }
      return;
    }
    _saving = true;
    if (mounted) setState(() => _autoSaveStatus = _AutoSaveStatus.saving);
    try {
      await ref
          .read(memoProvider.notifier)
          .updateMemo(
            widget.memoId,
            title: _titleController.text,
            bodyMd: _bodyController.text,
            snapshot: snapshot,
            snapshotSource: source,
          );
      _savedTitle = _titleController.text;
      _savedBody = _bodyController.text;
      clearMemoDraft(widget.memoId);
      if (!mounted) return;
      setState(() {
        _autoSaveStatus = _AutoSaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备忘录已保存')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _autoSaveStatus = _AutoSaveStatus.error);
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  Widget _buildAutoSaveStatus() {
    switch (_autoSaveStatus) {
      case _AutoSaveStatus.saving:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 6),
            Text('正在保存…', style: TextStyle(fontSize: 11)),
          ],
        );
      case _AutoSaveStatus.saved:
        final time = _lastSavedAt;
        final label = time == null
            ? '已保存'
            : '已保存 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        return Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.appColors.textSecondary,
          ),
        );
      case _AutoSaveStatus.error:
        return GestureDetector(
          onTap: () =>
              _performSave(snapshot: false, manual: false, source: 'auto'),
          child: const Text(
            '保存失败 · 点击重试',
            style: TextStyle(fontSize: 11, color: Colors.red),
          ),
        );
      case _AutoSaveStatus.none:
        return const SizedBox.shrink();
    }
  }

  /// 输入防抖后刷新预览面板，避免每次按键都重新解析 Markdown。
  void _schedulePreviewUpdate() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 150), () {
      _previewText.value = _bodyController.text;
    });
  }

  /// 分屏模式下按滚动比例双向同步编辑区和预览区。
  void _syncScroll({required bool fromEditor}) {
    if (_syncingScroll) return;
    final source = fromEditor
        ? _editorScrollController
        : _previewScrollController;
    final target = fromEditor
        ? _previewScrollController
        : _editorScrollController;
    if (!source.hasClients || !target.hasClients) return;
    final sourceMax = source.position.maxScrollExtent;
    final targetMax = target.position.maxScrollExtent;
    if (sourceMax <= 0 || targetMax <= 0) return;
    _syncingScroll = true;
    target.jumpTo(
      (source.offset / sourceMax * targetMax).clamp(0.0, targetMax),
    );
    _syncingScroll = false;
  }

  @override
  void dispose() {
    // 离开编辑器时冲刷未保存内容，并留下一个自动恢复版本。
    if (_isDirty) {
      final notifier = ref.read(memoProvider.notifier);
      notifier
          .updateMemo(
            widget.memoId,
            title: _titleController.text,
            bodyMd: _bodyController.text,
            snapshot: true,
            snapshotSource: 'auto',
          )
          .then((_) => clearMemoDraft(widget.memoId))
          .catchError((Object _) {});
    }
    _autoSaveTimer?.cancel();
    _draftTimer?.cancel();
    _bodyController.removeListener(_onContentChanged);
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _editorScrollController.dispose();
    _previewScrollController.dispose();
    _previewText.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _currentMemo => ref
      .watch(memoProvider)
      .valueOrNull
      ?.where((m) => m['id'] == widget.memoId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final memo = _currentMemo;
    if (memo == null) return const SizedBox.shrink();
    final isPrivate = memo['isPrivate'] == true;
    if (isPrivate && !MemoCryptoService.instance.isUnlocked) {
      return const Center(child: Text('该备忘录已加密，请先解锁隐私内容'));
    }
    if (!_loaded) {
      _loaded = true;
      var title = memo['title'] as String? ?? '';
      var body = memo['bodyMd'] as String? ?? '';
      if (isPrivate) {
        final encrypted = memo['encryptedPayload'] as String?;
        if (encrypted != null && encrypted.isNotEmpty) {
          try {
            final decoded = MemoCryptoService.instance.decryptText(encrypted);
            final separator = decoded.indexOf('\u0000');
            if (separator >= 0) {
              title = decoded.substring(0, separator);
              body = decoded.substring(separator + 1);
            }
          } catch (_) {
            // 密文损坏时保持空白编辑器，保存前由 provider 阻止覆盖。
          }
        }
      }
      _titleController.text = title;
      _bodyController.text = body;
      _previewText.value = body;
      _savedTitle = title;
      _savedBody = body;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkDraft(isPrivate),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.isMobile)
                IconButton(
                  tooltip: '返回备忘录列表',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _buildAutoSaveStatus(),
              const SizedBox(width: 4),
              if (!widget.isMobile)
                IconButton(
                  tooltip: '插入图片',
                  onPressed: _insertImage,
                  icon: const Icon(Icons.image_outlined),
                ),
              if (!widget.isMobile)
                IconButton(
                  tooltip: '附件管理',
                  onPressed: _showAttachmentsDialog,
                  icon: const Icon(Icons.attach_file),
                ),
              IconButton(
                tooltip: '更多操作',
                onPressed: () => _showMoreMenu(memo),
                icon: const Icon(Icons.more_vert),
              ),
              IconButton(
                tooltip: widget.preview ? '编辑 Markdown' : '预览 Markdown',
                onPressed: () => widget.onPreviewChanged(!widget.preview),
                icon: Icon(widget.preview ? Icons.edit : Icons.preview),
              ),
              IconButton(
                tooltip: '保存',
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const wideBreakpoint = 1000.0;
                final wide = constraints.maxWidth >= wideBreakpoint;
                final editorPane = TextField(
                  controller: _bodyController,
                  scrollController: _editorScrollController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '使用 Markdown 编写内容，支持表格、任务列表和图片',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                );
                if (!widget.preview) return editorPane;
                // 宽屏进入 Typora 风格分屏：左侧编辑、右侧实时预览、滚动同步；
                // 窄屏保持整屏切换预览。
                final previewPane = ValueListenableBuilder<String>(
                  valueListenable: _previewText,
                  builder: (context, text, _) => SingleChildScrollView(
                    controller: _previewScrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    child: MarkdownPreview(data: text),
                  ),
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: editorPane),
                      const VerticalDivider(width: 1),
                      Expanded(child: previewPane),
                    ],
                  );
                }
                return previewPane;
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(Map<String, dynamic> memo) {
    final pinned = memo['pinned'] == true;
    final archived = memo['archived'] == true;
    final aiAllowed = memo['aiAllowed'] == true;
    final isPrivate = memo['isPrivate'] == true;
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('更多操作'),
        children: [
          if (widget.isMobile) ...[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                _insertImage();
              },
              child: const Row(
                children: [
                  Icon(Icons.image_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('插入图片'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showAttachmentsDialog();
              },
              child: const Row(
                children: [
                  Icon(Icons.attach_file, size: 18),
                  SizedBox(width: 8),
                  Text('附件管理'),
                ],
              ),
            ),
          ],
          SimpleDialogOption(
            onPressed: () => _applyUpdate(pinned: !pinned, pop: dialogContext),
            child: Row(
              children: [
                const Icon(Icons.push_pin, size: 18),
                const SizedBox(width: 8),
                Text(pinned ? '取消置顶' : '置顶'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                _applyUpdate(archived: !archived, pop: dialogContext),
            child: Row(
              children: [
                const Icon(Icons.archive_outlined, size: 18),
                const SizedBox(width: 8),
                Text(archived ? '取消归档' : '归档'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showTagsDialog();
            },
            child: const Row(
              children: [
                Icon(Icons.label_outline, size: 18),
                SizedBox(width: 8),
                Text('标签管理'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showVersionHistoryDialog(isPrivate: isPrivate);
            },
            child: const Row(
              children: [
                Icon(Icons.history, size: 18),
                SizedBox(width: 8),
                Text('版本历史'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showAutoSaveSettings();
            },
            child: const Row(
              children: [
                Icon(Icons.settings_backup_restore, size: 18),
                SizedBox(width: 8),
                Text('自动保存设置'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                _applyUpdate(aiAllowed: !aiAllowed, pop: dialogContext),
            child: Row(
              children: [
                Icon(
                  aiAllowed ? Icons.smart_toy : Icons.smart_toy_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(aiAllowed ? '禁止 AI 读取本篇' : '允许 AI 读取本篇'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _save();
              await MemoDatabase.deleteMemo(widget.memoId);
              widget.onTrash();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已移到回收站')));
              }
            },
            child: const Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('移到回收站', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyUpdate({
    bool? pinned,
    bool? archived,
    bool? aiAllowed,
    required BuildContext pop,
  }) async {
    Navigator.pop(pop);
    try {
      await _save(silent: true);
      await ref
          .read(memoProvider.notifier)
          .updateMemo(
            widget.memoId,
            pinned: pinned,
            archived: archived,
            aiAllowed: aiAllowed,
          );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _showTagsDialog() async {
    final notifier = ref.read(memoProvider.notifier);
    final tags = await notifier.loadTags();
    final linked =
        (await MemoDatabase.getMemo(widget.memoId))?['tags'] as List? ?? [];
    final linkedIds = linked.map((t) => (t as Map)['id'] as String).toSet();
    if (!mounted) return;
    final selected = {...linkedIds};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('标签管理'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in tags)
                      FilterChip(
                        label: Text(tag['name'] as String? ?? ''),
                        selected: selected.contains(tag['id']),
                        onSelected: (value) => setDialogState(() {
                          value
                              ? selected.add(tag['id'] as String)
                              : selected.remove(tag['id']);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    final name = await showDialog<String>(
                      context: dialogContext,
                      builder: (context) {
                        final controller = TextEditingController();
                        return AlertDialog(
                          title: const Text('新建标签'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            onSubmitted: (value) =>
                                Navigator.pop(context, value),
                            decoration: const InputDecoration(
                              labelText: '标签名称',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(context, controller.text),
                              child: const Text('创建'),
                            ),
                          ],
                        );
                      },
                    );
                    if (name == null || name.trim().isEmpty) return;
                    try {
                      final tag = await notifier.createTag(name.trim());
                      setDialogState(() => selected.add(tag['id'] as String));
                    } catch (error) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('标签创建失败：$error')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新建标签'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await notifier.setTags(widget.memoId, selected.toList());
    }
  }

  Future<void> _showVersionHistoryDialog({required bool isPrivate}) async {
    final versions = await ref
        .read(memoProvider.notifier)
        .loadVersions(widget.memoId);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('版本历史（手动 20 个，自动 10 个）'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: versions.isEmpty
              ? const Center(child: Text('暂无历史版本'))
              : ListView.builder(
                  itemCount: versions.length,
                  itemBuilder: (context, index) {
                    final version = versions[index];
                    final time = version['createdAt'] as int?;
                    return ListTile(
                      leading: Text(
                        '#${version['versionNumber'] ?? index + 1}',
                      ),
                      title: Text(
                        _versionTitle(version, isPrivate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${version['source'] == 'auto' ? '自动' : '手动'} · ${formatMemoDate(time)}',
                        maxLines: 1,
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await _restoreVersion(
                            version,
                            isPrivate: isPrivate,
                          );
                          if (ok && dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        child: const Text('恢复'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _versionTitle(Map<String, dynamic> version, bool isPrivate) {
    if (!isPrivate) return version['title'] as String? ?? '(无标题)';
    final payload = version['encryptedPayload'] as String?;
    if (payload == null) return '(加密版本)';
    try {
      final decoded = MemoCryptoService.instance.decryptText(payload);
      final separator = decoded.indexOf('\u0000');
      return separator >= 0 ? decoded.substring(0, separator) : '(加密版本)';
    } catch (_) {
      return '(无法解密)';
    }
  }

  Future<bool> _restoreVersion(
    Map<String, dynamic> version, {
    required bool isPrivate,
  }) async {
    try {
      if (isPrivate) {
        final payload = version['encryptedPayload'] as String?;
        if (payload == null) throw StateError('该版本没有可恢复内容');
        final decoded = MemoCryptoService.instance.decryptText(payload);
        final separator = decoded.indexOf('\u0000');
        final title = separator >= 0 ? decoded.substring(0, separator) : '';
        final body = separator >= 0
            ? decoded.substring(separator + 1)
            : decoded;
        await ref
            .read(memoProvider.notifier)
            .updateMemo(widget.memoId, title: title, bodyMd: body);
      } else {
        await ref
            .read(memoProvider.notifier)
            .updateMemo(
              widget.memoId,
              title: version['title'] as String?,
              bodyMd: version['bodyMd'] as String?,
            );
      }
      _loaded = false;
      if (mounted) setState(() {});
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
      return false;
    }
  }

  Future<void> _insertImage() async {
    final memo = _currentMemo;
    if (memo == null) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    try {
      Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw StateError('无法读取所选图片');
      }
      final attachment = await MemoImageService.instance.saveImportedImage(
        filename: file.name,
        bytes: bytes,
        memoId: widget.memoId,
        isPrivate: memo['isPrivate'] == true,
      );
      final name = (attachment['filename'] as String?) ?? '图片';
      final markdown =
          '![${name.replaceAll(']', '')}](memo-attachment://${attachment['id']})';
      final offset = _bodyController.selection.baseOffset;
      final text = _bodyController.text;
      final insertAt = (offset < 0 || offset > text.length)
          ? text.length
          : offset;
      final leading =
          insertAt == 0 || text.substring(0, insertAt).endsWith('\n')
          ? ''
          : '\n\n';
      _bodyController.value = TextEditingValue(
        text:
            '${text.substring(0, insertAt)}$leading$markdown\n\n${text.substring(insertAt)}',
        selection: TextSelection.collapsed(
          offset: insertAt + markdown.length + 2,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片已插入，保存后开始上传')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('插入图片失败：$error')));
      }
    }
  }

  Future<void> _showAttachmentsDialog() async {
    final memo = _currentMemo;
    if (memo == null) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => _AttachmentsDialog(memoId: widget.memoId),
    );
    if (mounted) setState(() {});
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    _saving = true;
    if (mounted) setState(() {});
    try {
      await _performSave(snapshot: true, manual: !silent);
      if (!mounted) return;
      // 保存后触发附件上传队列（登录状态下）。
      final failure = await MemoImageService.instance.flushUploadQueue();
      if (!mounted) return;
      if (!silent && failure == null) {
        // _performSave 已展示“备忘录已保存”。
      } else if (failure != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('部分附件上传失败：\n$failure')));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }
}

class _AttachmentsDialog extends ConsumerStatefulWidget {
  const _AttachmentsDialog({required this.memoId});

  final String memoId;

  @override
  ConsumerState<_AttachmentsDialog> createState() => _AttachmentsDialogState();
}

class _AttachmentsDialogState extends ConsumerState<_AttachmentsDialog> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await MemoDatabase.getAttachments(memoId: widget.memoId);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AlertDialog(
      title: const Text('附件管理'),
      content: SizedBox(
        width: 460,
        height: 380,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Center(child: Text('本篇还没有附件'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final attachment = items[index];
                  final status =
                      attachment['uploadStatus'] as String? ?? 'pending';
                  final storageKey = attachment['storageKey'] as String?;
                  final isPrivate = attachment['isPrivate'] == true;
                  return ListTile(
                    leading: Icon(
                      attachment['mimeType'] == 'image/gif'
                          ? Icons.gif
                          : Icons.image_outlined,
                      size: 20,
                    ),
                    title: Text(
                      attachment['filename'] as String? ?? '（文件名已加密）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_humanSize(attachment['sizeBytes'] as int?)} · '
                      '${isPrivate ? '私密（端到端加密）' : '普通'} · '
                      '${status == 'uploaded' ? '已上传' : '待上传'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => _handleAction(action, attachment),
                      itemBuilder: (context) => [
                        if (status != 'uploaded')
                          const PopupMenuItem(
                            value: 'retry',
                            child: Text('立即上传'),
                          ),
                        if (storageKey != null && storageKey.isNotEmpty)
                          const PopupMenuItem(
                            value: 'share',
                            child: Text('创建分享链接'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除附件'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _handleAction(
    String action,
    Map<String, dynamic> attachment,
  ) async {
    final id = attachment['id'] as String;
    try {
      switch (action) {
        case 'retry':
          await MemoImageService.instance.retryUpload(id);
          _toast('附件已上传');
        case 'share':
          await _createShare(attachment);
        case 'delete':
          await MemoDatabase.updateAttachment(id, {'deleted': true});
          final storageKey = attachment['storageKey'] as String?;
          if (storageKey != null &&
              storageKey.isNotEmpty &&
              SyncService.isLoggedIn) {
            try {
              await MemoAttachmentService.instance.revokeShare('');
            } catch (_) {
              // 忽略：附件的远端对象删除走独立接口，失败不阻塞本地删除。
            }
          }
          _toast('附件已删除');
      }
      await _reload();
    } catch (error) {
      _toast('操作失败：$error');
    }
  }

  Future<void> _createShare(Map<String, dynamic> attachment) async {
    final passwordController = TextEditingController();
    var expiresDays = 7;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建分享链接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: expiresDays,
                decoration: const InputDecoration(labelText: '有效期'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 天')),
                  DropdownMenuItem(value: 7, child: Text('7 天')),
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                  DropdownMenuItem(value: 0, child: Text('永不过期')),
                ],
                onChanged: (value) =>
                    setDialogState(() => expiresDays = value ?? 7),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '访问密码（可选，至少 8 位）'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final password = passwordController.text;
    if (password.isNotEmpty && password.length < 8) {
      _toast('分享密码至少 8 位');
      return;
    }
    final token = await MemoAttachmentService.instance.createShare(
      objectKey: attachment['storageKey'] as String,
      expiresAt: expiresDays > 0
          ? DateTime.now().add(Duration(days: expiresDays))
          : null,
      password: password.isEmpty ? null : password,
    );
    final link = '${SyncService.serverUrl}/share/$token';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('分享链接已创建'),
        content: SelectableText(link),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _humanSize(int? bytes) {
    final value = bytes ?? 0;
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 编辑器自动保存状态；自动保存失败时提供点击重试入口。
enum _AutoSaveStatus { none, saving, saved, error }
