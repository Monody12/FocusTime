import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/data/database/memo_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/memos/providers/memo_provider.dart';
import 'package:focus_my_time/features/memos/services/memo_attachment_service.dart';
import 'package:focus_my_time/features/memos/services/memo_crypto_service.dart';
import 'package:focus_my_time/features/memos/services/memo_draft_service.dart';
import 'package:focus_my_time/features/memos/services/memo_diff.dart';
import 'package:focus_my_time/features/memos/services/memo_image_service.dart';
import 'package:focus_my_time/features/memos/presentation/widgets/markdown_preview.dart';

enum _MemoListMode { active, archived, trash }

enum _MemoViewMode { read, edit, split }

class MemoPage extends ConsumerStatefulWidget {
  const MemoPage({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends ConsumerState<MemoPage> {
  final _searchController = TextEditingController();
  final _folderFilterKey = GlobalKey();
  final _tagFilterKey = GlobalKey();
  final _sortFilterKey = GlobalKey();
  Timer? _searchDebounce;
  String? _selectedId;
  _MemoViewMode _viewMode = _MemoViewMode.read;
  _MemoListMode _listMode = _MemoListMode.active;
  bool _searchVisible = false;
  String? _selectedFolderId;
  String? _selectedTagId;
  MemoSortOption _sort = MemoSortOption.updatedDesc;
  List<Map<String, dynamic>> _folders = const [];
  List<Map<String, dynamic>> _tags = const [];
  List<Map<String, dynamic>>? _trashItems;

  static const _manageFoldersAction = '__manage_folders__';

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadTags();
    _loadListPreferences();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await ref.read(memoProvider.notifier).loadFolders();
      if (!mounted) return;
      setState(() => _folders = folders);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载文件夹失败：$error')));
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ref.read(memoProvider.notifier).loadTags();
      if (!mounted) return;
      setState(() => _tags = tags);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载标签失败：$error')));
    }
  }

  Future<void> _loadListPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _sort = MemoSortOption.fromStorage(prefs.getString('memo_sort'));
        _viewMode = _memoViewModeFromStorage(prefs.getString('memo_view_mode'));
      });
      _applyMemoFilter();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取备忘录排序设置失败：$error')));
    }
  }

  _MemoViewMode _memoViewModeFromStorage(String? value) {
    return _MemoViewMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => _MemoViewMode.read,
    );
  }

  Future<void> _setViewMode(_MemoViewMode mode) async {
    setState(() => _viewMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('memo_view_mode', mode.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存阅读模式设置失败：$error')));
    }
  }

  void _applyMemoFilter() {
    ref
        .read(memoProvider.notifier)
        .refresh(
          query: _searchController.text,
          folderId: _selectedFolderId,
          tagId: _selectedTagId,
          onlyArchived: _listMode == _MemoListMode.archived,
          sort: _sort,
        );
  }

  void _scheduleMemoFilter() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      _applyMemoFilter,
    );
  }

  void _setListMode(_MemoListMode mode) {
    setState(() {
      _listMode = mode;
      _selectedId = null;
    });
    if (mode == _MemoListMode.trash) {
      _loadTrash();
    } else {
      _applyMemoFilter();
    }
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
              Text(switch (_listMode) {
                _MemoListMode.active => '备忘录',
                _MemoListMode.archived => '已归档',
                _MemoListMode.trash => '回收站',
              }, style: Theme.of(context).textTheme.headlineSmall),
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
              if (!isMobile) ...[
                IconButton(
                  tooltip: _listMode == _MemoListMode.archived
                      ? '返回备忘录列表'
                      : '已归档备忘录',
                  onPressed: () => _setListMode(
                    _listMode == _MemoListMode.archived
                        ? _MemoListMode.active
                        : _MemoListMode.archived,
                  ),
                  icon: Icon(
                    _listMode == _MemoListMode.archived
                        ? Icons.arrow_back
                        : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  tooltip: crypto.isUnlocked ? '锁定隐私内容' : '解锁隐私内容',
                  onPressed: _toggleVault,
                  icon: Icon(
                    crypto.isUnlocked ? AppIcons.unlock : AppIcons.lock,
                  ),
                ),
                IconButton(
                  tooltip: _listMode == _MemoListMode.trash ? '返回备忘录列表' : '回收站',
                  onPressed: () => _setListMode(
                    _listMode == _MemoListMode.trash
                        ? _MemoListMode.active
                        : _MemoListMode.trash,
                  ),
                  icon: Icon(
                    _listMode == _MemoListMode.trash
                        ? Icons.arrow_back
                        : Icons.delete_outline,
                  ),
                ),
              ],
              if (_listMode == _MemoListMode.active)
                IconButton(
                  tooltip: '快速新建备忘录',
                  onPressed: _createQuickMemo,
                  icon: const Icon(AppIcons.add),
                ),
              if (_listMode == _MemoListMode.active && !isMobile)
                PopupMenuButton<String>(
                  tooltip: '新建选项',
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (_) => _createMemoWithOptions(context),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'advanced',
                      child: Row(
                        children: [
                          Icon(Icons.tune, size: 18),
                          SizedBox(width: 8),
                          Text('新建并设置文件夹、隐私或 AI'),
                        ],
                      ),
                    ),
                  ],
                ),
              if (isMobile)
                PopupMenuButton<String>(
                  tooltip: '更多备忘录操作',
                  onSelected: _handleHeaderMenu,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'archive',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _listMode == _MemoListMode.archived
                              ? Icons.notes
                              : Icons.archive_outlined,
                        ),
                        title: Text(
                          _listMode == _MemoListMode.archived ? '全部备忘录' : '已归档',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'vault',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          crypto.isUnlocked ? AppIcons.lock : AppIcons.unlock,
                        ),
                        title: Text(crypto.isUnlocked ? '锁定隐私内容' : '解锁隐私内容'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'trash',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _listMode == _MemoListMode.trash
                              ? Icons.notes
                              : Icons.delete_outline,
                        ),
                        title: Text(
                          _listMode == _MemoListMode.trash ? '全部备忘录' : '回收站',
                        ),
                      ),
                    ),
                    if (_listMode == _MemoListMode.active)
                      const PopupMenuItem(
                        value: 'advanced_create',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.tune),
                          title: Text('新建选项'),
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'close',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.close),
                        title: Text('返回任务界面'),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                )
              else
                IconButton(
                  tooltip: '返回任务界面',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        if (_listMode != _MemoListMode.trash) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFolderSelector(),
                        const SizedBox(width: 8),
                        _buildTagSelector(),
                        const SizedBox(width: 8),
                        _buildSortSelector(),
                      ],
                    ),
                  ),
                ),
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
                onChanged: (value) => _scheduleMemoFilter(),
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
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('备忘录加载失败'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _applyMemoFilter,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (items) => _listMode == _MemoListMode.trash
                ? _buildTrashList(_trashItems ?? const [])
                : isMobile
                ? _buildMobileMemoPane(items)
                : Row(
                    children: [
                      SizedBox(
                        width: 320,
                        child: items.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
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
                                viewMode: _viewMode,
                                onViewModeChanged: _setViewMode,
                                onTrash: () {
                                  setState(() => _selectedId = null);
                                  ref
                                      .read(memoProvider.notifier)
                                      .reloadCurrentView();
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

  void _handleHeaderMenu(String action) {
    switch (action) {
      case 'archive':
        _setListMode(
          _listMode == _MemoListMode.archived
              ? _MemoListMode.active
              : _MemoListMode.archived,
        );
      case 'vault':
        _toggleVault();
      case 'trash':
        _setListMode(
          _listMode == _MemoListMode.trash
              ? _MemoListMode.active
              : _MemoListMode.trash,
        );
      case 'advanced_create':
        _createMemoWithOptions(context);
      case 'close':
        widget.onClose();
    }
  }

  Widget _buildEmptyState() {
    final archived = _listMode == _MemoListMode.archived;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              archived ? Icons.archive_outlined : Icons.note_add_outlined,
              size: 36,
              color: context.appColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(archived ? '还没有已归档的备忘录' : '还没有备忘录'),
            if (!archived) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _createQuickMemo,
                icon: const Icon(Icons.add),
                label: const Text('新建备忘录'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFolderSelector() {
    return _buildFilterChip(
      key: _folderFilterKey,
      icon: Icons.folder_outlined,
      label: _currentFolderName,
      tooltip: '文件夹筛选：$_currentFolderName',
      maxLabelWidth: 160,
      onPressed: () async {
        final buttonContext = _folderFilterKey.currentContext;
        if (buttonContext == null) return;
        final value = await _showAnchoredMenu<String>(
          anchorContext: buttonContext,
          items: [
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
        );
        if (!mounted || value == null) return;
        if (value == _manageFoldersAction) {
          _showManageFoldersDialog();
          return;
        }
        setState(() => _selectedFolderId = value.isEmpty ? null : value);
        _applyMemoFilter();
      },
    );
  }

  Widget _buildTagSelector() {
    final selectedName = _selectedTagId == null
        ? '全部标签'
        : _tags
                  .where((tag) => tag['id'] == _selectedTagId)
                  .firstOrNull?['name']
                  ?.toString() ??
              '已删除标签';
    return _buildFilterChip(
      key: _tagFilterKey,
      icon: Icons.label_outline,
      label: selectedName,
      tooltip: '标签筛选：$selectedName',
      onPressed: () async {
        final buttonContext = _tagFilterKey.currentContext;
        if (buttonContext == null) return;
        final value = await _showAnchoredMenu<String>(
          anchorContext: buttonContext,
          items: [
            const PopupMenuItem(value: '', child: Text('全部标签')),
            for (final tag in _tags)
              PopupMenuItem(
                value: tag['id'] as String,
                child: Text(
                  tag['name'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
        if (!mounted || value == null) return;
        setState(() => _selectedTagId = value.isEmpty ? null : value);
        _applyMemoFilter();
      },
    );
  }

  Widget _buildSortSelector() {
    return _buildFilterChip(
      key: _sortFilterKey,
      icon: Icons.sort,
      label: _sortLabel(_sort),
      tooltip: '排序方式：${_sortLabel(_sort)}',
      onPressed: () async {
        final buttonContext = _sortFilterKey.currentContext;
        if (buttonContext == null) return;
        final value = await _showAnchoredMenu<MemoSortOption>(
          anchorContext: buttonContext,
          items: [
            for (final option in MemoSortOption.values)
              PopupMenuItem(value: option, child: Text(_sortLabel(option))),
          ],
        );
        if (!mounted || value == null) return;
        setState(() => _sort = value);
        _applyMemoFilter();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('memo_sort', value.storageValue);
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('保存排序设置失败：$error')));
        }
      },
    );
  }

  Future<T?> _showAnchoredMenu<T>({
    required BuildContext anchorContext,
    required List<PopupMenuEntry<T>> items,
  }) {
    final anchor = anchorContext.findRenderObject();
    final overlay = Overlay.of(anchorContext).context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox) {
      return Future<T?>.value();
    }
    final rect = Rect.fromPoints(
      anchor.localToGlobal(Offset.zero, ancestor: overlay),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    return showMenu<T>(
      context: anchorContext,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: items,
    );
  }

  Widget _buildFilterChip({
    required Key key,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    double maxLabelWidth = 140,
  }) {
    return Semantics(
      key: key,
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.appColors.text,
              side: BorderSide(color: context.appColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sortLabel(MemoSortOption option) => switch (option) {
    MemoSortOption.updatedDesc => '最近修改',
    MemoSortOption.updatedAsc => '最早修改',
    MemoSortOption.titleAsc => '名称 A-Z',
    MemoSortOption.titleDesc => '名称 Z-A',
    MemoSortOption.createdDesc => '最近创建',
    MemoSortOption.createdAsc => '最早创建',
  };

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
        return _buildEmptyState();
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _buildMemoTile(items[index]),
      );
    }
    return _MemoEditor(
      key: ValueKey(_selectedId),
      memoId: _selectedId!,
      viewMode: _viewMode == _MemoViewMode.split
          ? _MemoViewMode.read
          : _viewMode,
      isMobile: true,
      onBack: () => setState(() => _selectedId = null),
      onViewModeChanged: _setViewMode,
      onTrash: () {
        setState(() => _selectedId = null);
        ref.read(memoProvider.notifier).reloadCurrentView();
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
    final folderName = memo['folderName'] as String?;
    final tagNames =
        (memo['tagNames'] as List?)
            ?.map((tag) => tag.toString())
            .where((tag) => tag.isNotEmpty)
            .toList() ??
        const <String>[];
    final rawBody = locked ? '' : memo['bodyMd'] as String? ?? '';
    final snippet = rawBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    final metadata = <String>[
      _formatDate(memo['updatedAt'] as int?),
      if (folderName != null && folderName.isNotEmpty) folderName,
      if (tagNames.isNotEmpty) tagNames.take(2).map((tag) => '#$tag').join(' '),
    ].join(' · ');
    return ListTile(
      selected: _selectedId == id,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snippet.isNotEmpty)
            Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: _listMode == _MemoListMode.archived
          ? IconButton(
              tooltip: '取消归档',
              icon: const Icon(Icons.unarchive_outlined),
              onPressed: () async {
                try {
                  await ref.read(memoProvider.notifier).unarchive(id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('备忘录已取消归档')));
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('取消归档失败：$error')));
                }
              },
            )
          : null,
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
                  try {
                    await ref
                        .read(memoProvider.notifier)
                        .restore(memo['id'] as String);
                    await _loadTrash();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('备忘录已恢复')));
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('恢复失败：$error')));
                  }
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
    try {
      final items = await ref.read(memoProvider.notifier).loadTrash();
      if (mounted) setState(() => _trashItems = items);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载回收站失败：$error')));
    }
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
    try {
      await ref.read(memoProvider.notifier).purge(memo['id'] as String);
      await _loadTrash();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备忘录已彻底删除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('彻底删除失败：$error')));
    }
  }

  Future<void> _toggleVault() async {
    final crypto = MemoCryptoService.instance;
    if (crypto.isUnlocked) {
      crypto.lock();
      setState(() {});
      return;
    }
    try {
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
        ).showSnackBar(SnackBar(content: Text('隐私内容解锁失败：$error')));
      }
    }
  }

  Future<void> _createQuickMemo() async {
    try {
      final memo = await ref
          .read(memoProvider.notifier)
          .create(folderId: _selectedFolderId);
      if (!mounted) return;
      setState(() {
        _selectedId = memo['id'] as String;
        _viewMode = _MemoViewMode.edit;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('新建备忘录失败：$error')));
    }
  }

  Future<void> _createMemoWithOptions(BuildContext context) async {
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
                  setState(() {
                    _selectedId = memo['id'] as String;
                    _viewMode = _MemoViewMode.edit;
                  });
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
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onTrash,
    this.isMobile = false,
    this.onBack,
  });

  final String memoId;
  final _MemoViewMode viewMode;
  final ValueChanged<_MemoViewMode> onViewModeChanged;
  final VoidCallback onTrash;
  final bool isMobile;
  final VoidCallback? onBack;

  @override
  ConsumerState<_MemoEditor> createState() => _MemoEditorState();
}

class _MemoEditorState extends ConsumerState<_MemoEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocusNode = FocusNode();
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
  int? _knownUpdatedAt;
  _ExternalMemoChange? _externalChange;
  bool _syncingScroll = false;
  bool _loaded = false;
  bool _saving = false;
  bool _draftChecked = false;
  bool _draftWriteErrorShown = false;
  bool _autoSaveEnabled = true;
  bool _draggingImage = false;
  int _autoSaveDelayMs = 2500;
  late final void Function(ClipboardReadEvent) _pasteListener;

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_onContentChanged);
    _titleController.addListener(_onTitleChanged);
    _pasteListener = _handleWebPaste;
    ClipboardEvents.instance?.registerPasteEventListener(_pasteListener);
    _loadAutoSaveSettings();
    _loadLastAutoVersion();
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
    if (!_autoSaveEnabled || !_isDirty || _externalChange != null) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(Duration(milliseconds: _autoSaveDelayMs), () async {
      final now = DateTime.now();
      final snapshot =
          _lastAutoVersionAt == null ||
          now.difference(_lastAutoVersionAt!) >= const Duration(minutes: 5);
      final saved = await _performSave(
        snapshot: snapshot,
        manual: false,
        source: 'auto',
      );
      if (saved && snapshot) _lastAutoVersionAt = now;
    });
  }

  Future<void> _loadLastAutoVersion() async {
    try {
      final latest = await MemoDatabase.getLatestVersion(
        widget.memoId,
        source: 'auto',
      );
      final createdAt = latest?['createdAt'] as int?;
      if (createdAt != null) {
        _lastAutoVersionAt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      }
    } catch (_) {
      // 历史读取失败不阻塞编辑；保存失败时仍会在状态区提示。
    }
  }

  void _scheduleDraftWrite() {
    if (!_loaded || !_isDirty) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), () async {
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
                'savedAt': DateTime.now().millisecondsSinceEpoch,
                'payload': MemoCryptoService.instance.encryptText(
                  '${_titleController.text}\u0000${_bodyController.text}',
                ),
              }
            : {
                'private': false,
                'savedAt': DateTime.now().millisecondsSinceEpoch,
                'title': _titleController.text,
                'body': _bodyController.text,
              };
        await writeMemoDraft(widget.memoId, jsonEncode(data));
        _draftWriteErrorShown = false;
      } catch (error) {
        if (mounted && !_draftWriteErrorShown) {
          _draftWriteErrorShown = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('恢复草稿保存失败：$error')));
        }
      }
    });
  }

  Future<void> _clearDraft({bool reportError = true}) async {
    try {
      await clearMemoDraft(widget.memoId);
    } catch (error) {
      if (mounted && reportError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复草稿清理失败：$error')));
      }
    }
  }

  Future<void> _checkDraft(bool isPrivate) async {
    if (_draftChecked) return;
    _draftChecked = true;
    try {
      final raw = await readMemoDraft(widget.memoId);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      String title;
      String body;
      if (data['private'] == true) {
        if (!isPrivate) {
          await _clearDraft();
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
        await _clearDraft();
        return;
      }
      if (!mounted) return;
      final savedAt = data['savedAt'] as int?;
      final storedTitle = (_savedTitle ?? '').trim();
      final draftTitle = title.trim();
      final savedSnippet = (_savedBody ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final draftSnippet = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('检测到未保存的草稿'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (savedAt != null)
                  Text(
                    '草稿时间：${formatMemoDate(savedAt)}',
                    style: TextStyle(color: context.appColors.textSecondary),
                  ),
                const SizedBox(height: 12),
                Text(
                  draftTitle.isEmpty ? '未命名备忘录' : draftTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  draftSnippet.isEmpty ? '（正文为空）' : draftSnippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (savedSnippet.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '当前已保存：$savedSnippet',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showContentDiff(
                    title: '草稿与已保存内容比较',
                    beforeLabel: storedTitle.isEmpty ? '已保存内容' : storedTitle,
                    before: _savedBody ?? '',
                    afterLabel: draftTitle.isEmpty ? '恢复草稿' : draftTitle,
                    after: body,
                  ),
                  icon: const Icon(Icons.difference_outlined),
                  label: const Text('查看差异'),
                ),
              ],
            ),
          ),
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
        await _clearDraft();
      }
    } catch (error) {
      await _clearDraft(reportError: false);
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

  Future<bool> _performSave({
    required bool snapshot,
    required bool manual,
    String source = 'manual',
    bool force = false,
  }) async {
    if (_saving || (!_isDirty && !force)) {
      if (manual && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有需要保存的修改')));
      }
      return false;
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
      await _clearDraft();
      if (!mounted) return true;
      setState(() {
        _autoSaveStatus = _AutoSaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备忘录已保存')));
      }
      SyncService.triggerBackgroundSync();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _autoSaveStatus = _AutoSaveStatus.error);
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return false;
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  Widget _buildSaveStatus(Map<String, dynamic> memo) {
    if (_isDirty && !_autoSaveEnabled) {
      return Tooltip(
        message: '自动保存已关闭，离开后将保留恢复草稿，但不会更新正式内容',
        child: InkWell(
          onTap: _showAutoSaveSettings,
          child: const Text(
            '未保存 · 自动保存已关闭',
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
        ),
      );
    }
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
        return ValueListenableBuilder<SyncActivity>(
          valueListenable: SyncService.syncActivityListenable,
          builder: (context, activity, _) {
            final updatedAt = memo['updatedAt'] as int? ?? 0;
            final synced =
                SyncService.isLoggedIn &&
                updatedAt <= SyncService.memoLastSyncTime;
            final time = _lastSavedAt;
            final localLabel = time == null
                ? '已保存到本机'
                : '已保存到本机 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            final cloudLabel = !SyncService.isLoggedIn
                ? '未启用云同步'
                : synced
                ? '已同步'
                : activity == SyncActivity.syncing
                ? '正在同步…'
                : activity == SyncActivity.error
                ? '同步失败'
                : '等待同步';
            return Text(
              '$localLabel · $cloudLabel',
              style: TextStyle(
                fontSize: 11,
                color: activity == SyncActivity.error
                    ? Colors.red
                    : context.appColors.textSecondary,
              ),
            );
          },
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
    if (_isDirty && _autoSaveEnabled) {
      final notifier = ref.read(memoProvider.notifier);
      notifier
          .updateMemo(
            widget.memoId,
            title: _titleController.text,
            bodyMd: _bodyController.text,
            snapshot: true,
            snapshotSource: 'auto',
          )
          .then((_) => _clearDraft(reportError: false))
          .catchError((Object _) {});
    }
    _autoSaveTimer?.cancel();
    _draftTimer?.cancel();
    _bodyController.removeListener(_onContentChanged);
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    ClipboardEvents.instance?.unregisterPasteEventListener(_pasteListener);
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
      _knownUpdatedAt = memo['updatedAt'] as int?;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkDraft(isPrivate),
      );
    } else {
      _detectExternalChange(memo, isPrivate);
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
                  readOnly: widget.viewMode == _MemoViewMode.read,
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!widget.isMobile) ...[
                _buildSaveStatus(memo),
                const SizedBox(width: 4),
              ],
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
              SegmentedButton<_MemoViewMode>(
                segments: [
                  const ButtonSegment(
                    value: _MemoViewMode.read,
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                    tooltip: '阅读',
                  ),
                  const ButtonSegment(
                    value: _MemoViewMode.edit,
                    icon: Icon(Icons.edit_outlined, size: 18),
                    tooltip: '编辑 Markdown',
                  ),
                  if (!widget.isMobile)
                    const ButtonSegment(
                      value: _MemoViewMode.split,
                      icon: Icon(Icons.vertical_split_outlined, size: 18),
                      tooltip: '分屏编辑与预览',
                    ),
                ],
                selected: {widget.viewMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    widget.onViewModeChanged(selection.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              IconButton(
                tooltip: '保存',
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
              ),
            ],
          ),
          if (widget.isMobile)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                child: _buildSaveStatus(memo),
              ),
            ),
          const Divider(height: 1),
          if (_externalChange != null) _buildExternalChangeBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const wideBreakpoint = 1000.0;
                final wide = constraints.maxWidth >= wideBreakpoint;
                final editorPane = DropTarget(
                  enable: widget.viewMode != _MemoViewMode.read,
                  onDragEntered: (_) => setState(() => _draggingImage = true),
                  onDragExited: (_) => setState(() => _draggingImage = false),
                  onDragDone: (details) {
                    setState(() => _draggingImage = false);
                    unawaited(_insertDroppedImages(details.files));
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.keyV,
                            control: true,
                          ): _pasteFromSystemClipboard,
                          const SingleActivator(
                            LogicalKeyboardKey.keyV,
                            meta: true,
                          ): _pasteFromSystemClipboard,
                        },
                        child: TextField(
                          focusNode: _bodyFocusNode,
                          controller: _bodyController,
                          scrollController: _editorScrollController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: '使用 Markdown 编写内容，可粘贴或拖入图片',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      if (_draggingImage)
                        IgnorePointer(
                          child: ColoredBox(
                            color: context.appColors.accent.withValues(
                              alpha: 0.12,
                            ),
                            child: Center(
                              child: Text(
                                '松开以插入图片',
                                style: TextStyle(
                                  color: context.appColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
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
                if (widget.viewMode == _MemoViewMode.edit) return editorPane;
                if (widget.viewMode == _MemoViewMode.split && wide) {
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

  void _detectExternalChange(Map<String, dynamic> memo, bool isPrivate) {
    final updatedAt = memo['updatedAt'] as int?;
    if (updatedAt == null || updatedAt == _knownUpdatedAt || _saving) return;
    _knownUpdatedAt = updatedAt;
    var title = memo['title'] as String? ?? '';
    var body = memo['bodyMd'] as String? ?? '';
    if (isPrivate) {
      final encrypted = memo['encryptedPayload'] as String?;
      if (encrypted == null || encrypted.isEmpty) return;
      try {
        final decoded = MemoCryptoService.instance.decryptText(encrypted);
        final separator = decoded.indexOf('\u0000');
        title = separator < 0 ? '' : decoded.substring(0, separator);
        body = separator < 0 ? decoded : decoded.substring(separator + 1);
      } catch (_) {
        return;
      }
    }
    if (title == _savedTitle && body == _savedBody) return;
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _externalChange = _ExternalMemoChange(
          title: title,
          body: body,
          updatedAt: updatedAt,
        );
      });
    });
  }

  Widget _buildExternalChangeBanner() {
    final change = _externalChange!;
    final actions = <Widget>[
      TextButton(
        onPressed: () => _showContentDiff(
          title: '与其他设备版本比较',
          beforeLabel: '当前编辑',
          before: _bodyController.text,
          afterLabel: '其他设备',
          after: change.body,
        ),
        child: const Text('比较'),
      ),
      TextButton(onPressed: _useExternalChange, child: const Text('采用远端')),
      FilledButton.tonal(
        onPressed: _keepLocalChange,
        child: const Text('保留本地'),
      ),
    ];
    return Material(
      color: context.appColors.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final message = Row(
              children: [
                Icon(
                  Icons.sync_problem,
                  size: 18,
                  color: context.appColors.warning,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('其他设备有更新，当前编辑内容尚未被覆盖')),
              ],
            );
            if (constraints.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  message,
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 4,
                    children: actions,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: message),
                const SizedBox(width: 8),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _useExternalChange() async {
    final change = _externalChange;
    if (change == null) return;
    _titleController.text = change.title;
    _bodyController.text = change.body;
    _previewText.value = change.body;
    _savedTitle = change.title;
    _savedBody = change.body;
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      _externalChange = null;
      _autoSaveStatus = _AutoSaveStatus.saved;
    });
  }

  Future<void> _keepLocalChange() async {
    final saved = await _performSave(
      snapshot: true,
      manual: false,
      source: 'conflict',
      force: true,
    );
    if (!saved || !mounted) return;
    setState(() => _externalChange = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保留本地内容，远端版本已存入冲突历史')));
  }

  Future<void> _showContentDiff({
    required String title,
    required String beforeLabel,
    required String before,
    required String afterLabel,
    required String after,
  }) async {
    final lines = buildMemoLineDiff(before, after);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$beforeLabel → $afterLabel'),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: context.appColors.surfaceElevated,
                  child: SelectionArea(
                    child: ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final prefix = switch (line.kind) {
                          MemoDiffKind.unchanged => '  ',
                          MemoDiffKind.added => '+ ',
                          MemoDiffKind.removed => '- ',
                        };
                        final color = switch (line.kind) {
                          MemoDiffKind.unchanged => context.appColors.text,
                          MemoDiffKind.added => context.appColors.success,
                          MemoDiffKind.removed => Colors.red,
                        };
                        return Text(
                          '$prefix${line.text}',
                          style: TextStyle(
                            color: color,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
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
              try {
                if (_isDirty) {
                  final saved = await _performSave(
                    snapshot: true,
                    manual: true,
                  );
                  if (!saved) return;
                }
                await MemoDatabase.deleteMemo(widget.memoId);
                widget.onTrash();
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已移到回收站')));
              } catch (error) {
                _toast('移到回收站失败：$error');
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
    late final List<Map<String, dynamic>> tags;
    late final List<dynamic> linked;
    try {
      tags = await notifier.loadTags();
      linked =
          (await MemoDatabase.getMemo(widget.memoId))?['tags'] as List? ?? [];
    } catch (error) {
      _toast('标签加载失败：$error');
      return;
    }
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
      try {
        await notifier.setTags(widget.memoId, selected.toList());
        _toast('标签已更新');
      } catch (error) {
        _toast('标签保存失败：$error');
      }
    }
  }

  Future<void> _showVersionHistoryDialog({required bool isPrivate}) async {
    late final List<Map<String, dynamic>> versions;
    try {
      versions = await ref
          .read(memoProvider.notifier)
          .loadVersions(widget.memoId);
    } catch (error) {
      _toast('版本历史加载失败：$error');
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('版本历史'),
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
                        '${_versionSourceLabel(version['source'] as String?)} · ${formatMemoDate(time)}',
                        maxLines: 1,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final restore = await _showVersionPreviewDialog(
                          version,
                          isPrivate: isPrivate,
                        );
                        if (restore != true) return;
                        final ok = await _restoreVersion(
                          version,
                          isPrivate: isPrivate,
                        );
                        if (ok && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
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

  String _versionSourceLabel(String? source) => switch (source) {
    'auto' => '自动恢复点',
    'conflict' => '跨端冲突',
    _ => '手动保存',
  };

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

  String _versionBody(Map<String, dynamic> version, bool isPrivate) {
    if (!isPrivate) return version['bodyMd'] as String? ?? '';
    final payload = version['encryptedPayload'] as String?;
    if (payload == null) return '';
    try {
      final decoded = MemoCryptoService.instance.decryptText(payload);
      final separator = decoded.indexOf('\u0000');
      return separator >= 0 ? decoded.substring(separator + 1) : decoded;
    } catch (_) {
      return '';
    }
  }

  Future<bool?> _showVersionPreviewDialog(
    Map<String, dynamic> version, {
    required bool isPrivate,
  }) {
    final title = _versionTitle(version, isPrivate);
    final body = _versionBody(version, isPrivate);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title.isEmpty ? '未命名版本' : title),
        content: SizedBox(
          width: 680,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_versionSourceLabel(version['source'] as String?)} · ${formatMemoDate(version['createdAt'] as int?)}',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: MarkdownPreview(data: body),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showContentDiff(
              title: '与当前内容比较',
              beforeLabel: '历史版本',
              before: body,
              afterLabel: '当前内容',
              after: _bodyController.text,
            ),
            icon: const Icon(Icons.difference_outlined),
            label: const Text('比较差异'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore),
            label: const Text('恢复此版本'),
          ),
        ],
      ),
    );
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
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw StateError('无法读取所选图片');
      }
      await _insertImageBytes(filename: file.name, bytes: bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('插入图片失败：$error')));
      }
    }
  }

  Future<void> _insertDroppedImages(List<DropItem> files) async {
    final supported = files.where((file) {
      final extension = file.name.split('.').last.toLowerCase();
      return const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension);
    }).toList();
    if (supported.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请拖入 PNG、JPEG、WebP 或 GIF 图片')),
      );
      return;
    }
    for (final file in supported) {
      try {
        await _insertImageBytes(
          filename: file.name,
          bytes: await file.readAsBytes(),
          showSuccess: false,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('插入 ${file.name} 失败：$error')));
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已插入 ${supported.length} 张图片')));
  }

  Future<void> _handleWebPaste(ClipboardReadEvent event) async {
    if (!_bodyFocusNode.hasFocus || widget.viewMode == _MemoViewMode.read) {
      return;
    }
    try {
      final reader = await event.getClipboardReader();
      await _insertClipboardContent(reader);
    } catch (error) {
      _toast('粘贴内容读取失败：$error');
    }
  }

  Future<void> _pasteFromSystemClipboard() async {
    if (ClipboardEvents.instance != null) return;
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    try {
      await _insertClipboardContent(await clipboard.read());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取剪贴板失败：$error')));
    }
  }

  Future<void> _insertClipboardContent(ClipboardReader reader) async {
    final image = await _readClipboardPng(reader);
    if (image != null) {
      await _insertImageBytes(filename: 'clipboard.png', bytes: image);
      return;
    }
    final text = reader.canProvide(Formats.plainText)
        ? await reader.readValue(Formats.plainText)
        : null;
    if (text != null && text.isNotEmpty) _insertTextAtSelection(text);
  }

  Future<Uint8List?> _readClipboardPng(DataReader reader) async {
    if (!reader.canProvide(Formats.png)) return null;
    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      Formats.png,
      (file) async {
        try {
          if (!completer.isCompleted) completer.complete(await file.readAll());
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    return progress == null ? null : completer.future;
  }

  Future<void> _insertImageBytes({
    required String filename,
    required Uint8List bytes,
    bool showSuccess = true,
  }) async {
    final memo = _currentMemo;
    if (memo == null) return;
    final attachment = await MemoImageService.instance.saveImportedImage(
      filename: filename,
      bytes: bytes,
      memoId: widget.memoId,
      isPrivate: memo['isPrivate'] == true,
    );
    final name = (attachment['filename'] as String?) ?? '图片';
    final markdown =
        '![${name.replaceAll(']', '')}](memo-attachment://${attachment['id']})';
    _insertTextAtSelection(markdown, block: true);
    if (showSuccess && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已插入，保存后开始上传')));
    }
  }

  void _insertTextAtSelection(String value, {bool block = false}) {
    final offset = _bodyController.selection.baseOffset;
    final text = _bodyController.text;
    final insertAt = (offset < 0 || offset > text.length)
        ? text.length
        : offset;
    final leading =
        block && insertAt > 0 && !text.substring(0, insertAt).endsWith('\n')
        ? '\n\n'
        : '';
    final trailing = block ? '\n\n' : '';
    final inserted = '$leading$value$trailing';
    _bodyController.value = TextEditingValue(
      text:
          '${text.substring(0, insertAt)}$inserted${text.substring(insertAt)}',
      selection: TextSelection.collapsed(offset: insertAt + inserted.length),
    );
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    if (_externalChange != null) {
      await _keepLocalChange();
      return;
    }
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
    } catch (error) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存附件状态失败：$error')));
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
    try {
      final items = await MemoDatabase.getAttachments(memoId: widget.memoId);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      _toast('附件列表加载失败：$error');
    }
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

class _ExternalMemoChange {
  const _ExternalMemoChange({
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String title;
  final String body;
  final int updatedAt;
}
