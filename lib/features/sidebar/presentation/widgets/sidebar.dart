import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Sidebar extends ConsumerStatefulWidget {
  final VoidCallback? onListChanged;
  final double topPadding;
  final bool showRightBorder;

  const Sidebar({
    super.key,
    this.onListChanged,
    this.topPadding = 8,
    this.showRightBorder = true,
  });

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> with WidgetsBindingObserver {
  bool _showNewList = false;
  bool _isCreatingList = false;
  final _newListController = TextEditingController();
  String _newListDraft = '';
  bool _keyboardWasVisible = false;
  final _scrollController = ScrollController();
  final _newListKey = GlobalKey();
  final _editListKey = GlobalKey();
  String? _editingListId;
  final _editController = TextEditingController();
  String? _dragHoverListId;

  // FocusNode 用于监听新建清单输入框的失焦事件
  late FocusNode _newListFocusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newListFocusNode = FocusNode();
    // 监听新建清单输入框的失焦事件：取消输入框并保留草稿，提交动作才真正创建。
    _newListFocusNode.addListener(_onNewListFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _newListFocusNode.removeListener(_onNewListFocusChange);
    _newListFocusNode.dispose();
    _scrollController.dispose();
    _newListController.dispose();
    _editController.dispose();
    super.dispose();
  }

  // 新建清单输入框失焦时的处理逻辑
  void _onNewListFocusChange() {
    if (!_newListFocusNode.hasFocus && _showNewList && !_isCreatingList) {
      _cancelCreatingList();
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showNewList || !_isMobile) return;
      final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
      if (_keyboardWasVisible && !keyboardVisible) {
        _cancelCreatingList(unfocus: false);
      }
      _keyboardWasVisible = keyboardVisible;
    });
  }

  bool get _isMobile =>
      Theme.of(context).platform == TargetPlatform.android ||
      Theme.of(context).platform == TargetPlatform.iOS;

  void _startCreatingList() {
    setState(() {
      _showNewList = true;
      _newListController.text = _newListDraft;
      _newListController.selection = TextSelection.collapsed(
        offset: _newListController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _newListFocusNode.requestFocus();
      _keyboardWasVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
      _ensureInputVisible(_newListKey);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ensureInputVisible(_newListKey);
    });
  }

  void _ensureInputVisible(GlobalKey key) {
    final inputContext = key.currentContext;
    if (inputContext == null) return;
    Scrollable.ensureVisible(
      inputContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: _isMobile ? 0.45 : 0.85,
    );
  }

  void _cancelCreatingList({bool unfocus = true}) {
    _newListDraft = _newListController.text;
    if (unfocus) {
      _newListFocusNode.unfocus();
    }
    if (!mounted) return;
    setState(() => _showNewList = false);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = _isMobile;
    final keyboardBottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final systemLists = taskState.lists.where((l) => l.isSystem).toList();
    final topLists =
        taskState.lists.where((l) => l.pinned && !l.hidden).toList()..sort(
          (a, b) =>
              (a.topOrder ?? a.sortOrder).compareTo(b.topOrder ?? b.sortOrder),
        );
    final customLists = taskState.lists
        .where((l) => !l.isSystem && !l.pinned)
        .toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.appColors.sidebar,
        border: widget.showRightBorder
            ? Border(right: BorderSide(color: context.appColors.border))
            : null,
      ),
      child: Column(
        children: [
          SizedBox(height: widget.topPadding),
          Expanded(
            child: ListView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                0,
                8,
                0,
                8 + (isMobile ? keyboardBottomInset : 0),
              ),
              children: [
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) {
                    final listIds = topLists.map((l) => l.id).toList();
                    final item = listIds.removeAt(oldIndex);
                    listIds.insert(newIndex, item);
                    taskNotifier.reorderTopLists(listIds);
                  },
                  children: topLists.asMap().entries.map((entry) {
                    final index = entry.key;
                    final list = entry.value;
                    final item = _buildListItem(
                      context,
                      icon: AppIcons.taskListIcon(list.iconKey),
                      label: list.name,
                      isSelected: taskState.currentListId == list.id,
                      onTap: () {
                        taskNotifier.setCurrentList(
                          list.id,
                          _viewTypeForList(list),
                        );
                        widget.onListChanged?.call();
                      },
                      onLongPress: () =>
                          _showTopListActionsSheet(context, list),
                      onSecondaryTapDown: (position) =>
                          _showTopListContextMenu(context, position, list),
                      isDark: isDark,
                      isMobile: isMobile,
                    );
                    if (isMobile) {
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey('top-${list.id}'),
                        index: index,
                        child: item,
                      );
                    }
                    return ReorderableDragStartListener(
                      key: ValueKey('top-${list.id}'),
                      index: index,
                      child: item,
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    '清单',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),

                // Custom lists (as drop targets for task drag-and-drop, and reorderable)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorderItem: (oldIndex, newIndex) {
                    final listIds = customLists.map((l) => l.id).toList();
                    final item = listIds.removeAt(oldIndex);
                    listIds.insert(newIndex, item);
                    taskNotifier.reorderLists(
                      listIds,
                      offset: systemLists.length,
                    );
                  },
                  // buildDefaultDragHandles: false，由 ReorderableDragStartListener 接管
                  buildDefaultDragHandles: false,
                  children: customLists.asMap().entries.map((entry) {
                    final index = entry.key;
                    final list = entry.value;
                    if (_editingListId == list.id) {
                      return SizedBox(
                        key: ValueKey('edit-${list.id}'),
                        child: _buildEditingItem(list.id, list.name, isDark),
                      );
                    }
                    // 用 ReorderableDragStartListener 包裹整个项目，鼠标按住即可拖动排序
                    // 根据平台选择拖拽监听器：移动端使用长按触发，防止干扰滑动翻页；桌面端使用立即触发。
                    final Widget listItem = _buildDraggableListItem(
                      context,
                      list: list,
                      isSelected: taskState.currentListId == list.id,
                      isHovering: _dragHoverListId == list.id,
                      onTap: () {
                        taskNotifier.setCurrentList(list.id, 'custom');
                        widget.onListChanged?.call();
                      },
                      onHover: (hovering) {
                        setState(() {
                          _dragHoverListId = hovering ? list.id : null;
                        });
                      },
                      onAccept: (taskId) async {
                        try {
                          await taskNotifier.updateTask(taskId, {
                            'listId': list.id,
                          });
                          widget.onListChanged?.call();
                        } catch (_) {
                          _showErrorSnackBar('移动任务失败，请重试');
                        }
                      },
                      isDark: isDark,
                      isMobile: isMobile,
                    );

                    if (isMobile) {
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(list.id),
                        index: index,
                        child: listItem,
                      );
                    }

                    return ReorderableDragStartListener(
                      key: ValueKey(list.id),
                      index: index,
                      child: listItem,
                    );
                  }).toList(),
                ),

                // New list input
                if (_showNewList)
                  Padding(
                    key: _newListKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _newListController,
                      focusNode: _newListFocusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '清单名称...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) => _createList(),
                      onTapOutside: (_) => _cancelCreatingList(),
                    ),
                  )
                else
                  _buildAddButton(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 系统清单项（不可作为拖拽目标）
  Widget _buildListItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    ValueChanged<Offset>? onSecondaryTapDown,
    required bool isDark,
    required bool isMobile,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTapDown: isMobile || onSecondaryTapDown == null
          ? null
          : (details) => onSecondaryTapDown(details.globalPosition),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: isSelected
                ? BoxDecoration(
                    color: context.appColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appColors.border),
                  )
                : null,
            child: Row(
              children: [
                AppIcon(
                  icon,
                  size: AppIconSizes.nav,
                  color: isSelected
                      ? context.appColors.text
                      : context.appColors.textSecondary,
                ),
                const SizedBox(width: AppIconSpacing.labelGap),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? (context.appColors.text)
                          : (context.appColors.textSecondary),
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _viewTypeForList(TaskList list) {
    switch (list.id) {
      case 'system-my-day':
        return 'my-day';
      case 'system-important':
        return 'important';
      case 'system-all-tasks':
        return 'all-tasks';
      default:
        return 'custom';
    }
  }

  // 自定义清单项（可作为拖拽目标接收任务）
  Widget _buildDraggableListItem(
    BuildContext context, {
    required TaskList list,
    required bool isSelected,
    required bool isHovering,
    required VoidCallback onTap,
    required Function(bool) onHover,
    required Function(String) onAccept,
    required bool isDark,
    required bool isMobile,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        onHover(true);
        return true;
      },
      onLeave: (_) {
        onHover(false);
      },
      onAcceptWithDetails: (details) {
        onHover(false);
        onAccept(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          onSecondaryTapDown: isMobile
              ? null
              : (details) => _showContextMenu(
                  context,
                  details.globalPosition,
                  list.id,
                  list.name,
                ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: isSelected || isHovering
                    ? BoxDecoration(
                        color: context.appColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.appColors.border),
                      )
                    : null,
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.taskListIcon(list.iconKey),
                      size: AppIconSizes.nav,
                      color: isSelected
                          ? context.appColors.text
                          : context.appColors.textSecondary,
                    ),
                    const SizedBox(width: AppIconSpacing.labelGap),
                    Expanded(
                      child: Text(
                        list.name,
                        style: TextStyle(
                          color: isSelected
                              ? (context.appColors.text)
                              : (context.appColors.textSecondary),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isHovering)
                      Icon(
                        AppIcons.listReceive,
                        size: AppIconSizes.nav,
                        color: context.appColors.accent,
                      ),
                    if (isMobile)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            _showListActionsSheet(context, list.id, list.name),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AppIcon(
                            AppIcons.more,
                            size: AppIconSizes.nav,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 编辑中清单项（内联输入框）
  Widget _buildEditingItem(String listId, String currentName, bool isDark) {
    return Padding(
      key: _editListKey,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _editController,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onSubmitted: (_) => _renameList(listId),
      ),
    );
  }

  /// 显示右键菜单（适用于桌面端）
  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    String listId,
    String listName,
  ) {
    final taskState = ref.read(taskProvider);
    final list = taskState.lists.where((l) => l.id == listId).firstOrNull;
    if (list == null) return;
    // 获取 Overlay 的 RenderBox 以计算相对位置
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40), // 在点击位置周围创建一个小的矩形区域
        Offset.zero & overlay.size,
      ),
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 8,
      items: [
        PopupMenuItem<String>(
          value: 'rename',
          height: 36,
          child: Row(
            children: [
              AppIcon(
                AppIcons.edit,
                size: AppIconSizes.compact,
                color: context.appColors.text,
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Text(
                '重命名',
                style: TextStyle(fontSize: 13, color: context.appColors.text),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pin',
          height: 36,
          child: Row(
            children: [
              AppIcon(
                AppIcons.playlistAdd,
                size: AppIconSizes.compact,
                color: context.appColors.text,
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Text(
                '置顶到顶部',
                style: TextStyle(fontSize: 13, color: context.appColors.text),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'icon',
          height: 36,
          child: Row(
            children: [
              AppIcon(
                AppIcons.flag,
                size: AppIconSizes.compact,
                color: context.appColors.text,
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Text(
                '更换图标',
                style: TextStyle(fontSize: 13, color: context.appColors.text),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'archive',
          height: 36,
          child: Row(
            children: [
              AppIcon(
                AppIcons.archive,
                size: AppIconSizes.compact,
                color: context.appColors.text,
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Text(
                '归档',
                style: TextStyle(fontSize: 13, color: context.appColors.text),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              AppIcon(
                AppIcons.delete,
                size: AppIconSizes.compact,
                color: Colors.red,
              ),
              SizedBox(width: AppIconSpacing.labelGap),
              Text('删除', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'rename') {
        _startEditing(listId, listName);
      } else if (value == 'pin') {
        _pinList(list);
      } else if (value == 'icon') {
        _showIconPicker(list);
      } else if (value == 'archive') {
        _confirmArchiveList(this.context, listId, listName);
      } else if (value == 'delete') {
        _confirmDeleteList(this.context, listId, listName);
      }
    });
  }

  void _showListActionsSheet(
    BuildContext context,
    String listId,
    String listName,
  ) {
    final parentContext = context;
    final list = ref
        .read(taskProvider)
        .lists
        .where((l) => l.id == listId)
        .firstOrNull;
    if (list == null) return;
    showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const AppIcon(AppIcons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) _startEditing(listId, listName);
                  });
                },
              ),
              ListTile(
                leading: const AppIcon(AppIcons.playlistAdd),
                title: const Text('置顶到顶部'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) _pinList(list);
                  });
                },
              ),
              ListTile(
                leading: const AppIcon(AppIcons.flag),
                title: const Text('更换图标'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) _showIconPicker(list);
                  });
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const AppIcon(AppIcons.archive),
                title: const Text('归档'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) {
                      _confirmArchiveList(this.context, listId, listName);
                    }
                  });
                },
              ),
              ListTile(
                leading: const AppIcon(AppIcons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) {
                      _confirmDeleteList(this.context, listId, listName);
                    }
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTopListContextMenu(
    BuildContext context,
    Offset globalPosition,
    TaskList list,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 8,
      items: [
        _topMenuItem('rename', AppIcons.edit, '重命名'),
        _topMenuItem('icon', AppIcons.flag, '更换图标'),
        if (list.isSystem)
          _topMenuItem('hide', AppIcons.playlistRemove, '隐藏预设清单')
        else
          _topMenuItem('unpin', AppIcons.playlistRemove, '取消置顶'),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      _handleTopListAction(this.context, list, value);
    });
  }

  PopupMenuItem<String> _topMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          AppIcon(
            icon,
            size: AppIconSizes.compact,
            color: context.appColors.text,
          ),
          const SizedBox(width: AppIconSpacing.labelGap),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: context.appColors.text),
          ),
        ],
      ),
    );
  }

  void _showTopListActionsSheet(BuildContext context, TaskList list) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const AppIcon(AppIcons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) _startEditing(list.id, list.name);
                  });
                },
              ),
              ListTile(
                leading: const AppIcon(AppIcons.flag),
                title: const Text('更换图标'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) _showIconPicker(list);
                  });
                },
              ),
              ListTile(
                leading: const AppIcon(AppIcons.playlistRemove),
                title: Text(list.isSystem ? '隐藏预设清单' : '取消置顶'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.delayed(Duration.zero, () {
                    if (mounted) {
                      _handleTopListAction(
                        this.context,
                        list,
                        list.isSystem ? 'hide' : 'unpin',
                      );
                    }
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleTopListAction(
    BuildContext context,
    TaskList list,
    String action,
  ) {
    if (action == 'rename') {
      _startEditing(list.id, list.name);
    } else if (action == 'icon') {
      _showIconPicker(list);
    } else if (action == 'hide') {
      _hideSystemList(context, list);
    } else if (action == 'unpin') {
      _unpinList(list);
    }
  }

  // 新建清单按钮
  Widget _buildAddButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startCreatingList,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                AppIcons.listAdd,
                size: AppIconSizes.nav,
                color: context.appColors.textSecondary,
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Text(
                '新建清单',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmArchiveList(
    BuildContext context,
    String listId,
    String listName,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.appColors.surface,
          title: Text('归档清单', style: TextStyle(color: context.appColors.text)),
          content: Text(
            '归档 "$listName" 后，这个清单和其中的任务会从当前列表中隐藏。之后可在设置中恢复或删除。',
            style: TextStyle(color: context.appColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _archiveList(listId);
              },
              child: const Text('归档'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteList(
    BuildContext context,
    String listId,
    String listName,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.appColors.surface,
          title: Text('删除清单', style: TextStyle(color: context.appColors.text)),
          content: Text(
            '确定要删除 "$listName" 吗？该清单下的所有任务也会被删除。',
            style: TextStyle(color: context.appColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteList(listId);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  void _startEditing(String listId, String currentName) {
    setState(() {
      _editingListId = listId;
      _editController.text = currentName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureInputVisible(_editListKey);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ensureInputVisible(_editListKey);
    });
  }

  void _renameList(String listId) async {
    final name = _editController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _editingListId = null;
        _editController.clear();
      });
      return;
    }

    try {
      await ref.read(taskProvider.notifier).updateList(listId, name);
      if (!mounted) return;
      setState(() {
        _editingListId = null;
        _editController.clear();
      });
    } catch (_) {
      _showErrorSnackBar('重命名清单失败，请重试');
    }
  }

  void _deleteList(String listId) async {
    try {
      await ref.read(taskProvider.notifier).deleteList(listId);
      if (!mounted) return;
      final taskState = ref.read(taskProvider);
      if (taskState.currentListId == listId) {
        await ref
            .read(taskProvider.notifier)
            .setCurrentList('system-my-day', 'my-day');
      }
      widget.onListChanged?.call();
    } catch (_) {
      _showErrorSnackBar('删除清单失败，请重试');
    }
  }

  Future<void> _archiveList(String listId) async {
    try {
      await ref.read(taskProvider.notifier).archiveList(listId);
      if (!mounted) return;
      final taskState = ref.read(taskProvider);
      if (taskState.currentListId == listId) {
        await ref
            .read(taskProvider.notifier)
            .setCurrentList('system-my-day', 'my-day');
      }
      widget.onListChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清单已归档，可在设置中恢复')));
    } catch (_) {
      _showErrorSnackBar('归档清单失败，请重试');
    }
  }

  Future<bool> _showTopListFeatureIntro() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('topListCustomizationIntroDismissed') == true) {
      return true;
    }
    if (!mounted) return false;
    var dontShowAgain = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.appColors.surface,
          title: Text(
            '顶部清单自定义',
            style: TextStyle(color: context.appColors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你可以把常用自定义清单置顶到“我的一天、重要、任务”所在区域，给它们换图标并拖动排序。隐藏系统预设清单后，可在设置中的任务栏设置恢复。置顶清单会同步到账号数据，多端同步后立即生效。',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: dontShowAgain,
                onChanged: (value) {
                  setDialogState(() => dontShowAgain = value == true);
                },
                title: Text(
                  '不再显示',
                  style: TextStyle(color: context.appColors.text),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && dontShowAgain) {
      await prefs.setBool('topListCustomizationIntroDismissed', true);
    }
    return accepted == true;
  }

  Future<void> _pinList(TaskList list) async {
    final accepted = await _showTopListFeatureIntro();
    if (!accepted) return;
    try {
      await ref.read(taskProvider.notifier).pinList(list.id);
      _showErrorSnackBar('已置顶到顶部清单');
    } catch (_) {
      _showErrorSnackBar('置顶清单失败，请重试');
    }
  }

  Future<void> _unpinList(TaskList list) async {
    try {
      await ref.read(taskProvider.notifier).unpinList(list.id);
      _showErrorSnackBar('已取消置顶');
    } catch (_) {
      _showErrorSnackBar('取消置顶失败，请重试');
    }
  }

  Future<void> _hideSystemList(BuildContext context, TaskList list) async {
    final accepted = await _showTopListFeatureIntro();
    if (!accepted) return;
    try {
      await ref.read(taskProvider.notifier).hideSystemList(list.id);
      if (!mounted) return;
      _showErrorSnackBar('已隐藏预设清单，可在设置的任务栏设置中恢复');
    } catch (_) {
      _showErrorSnackBar('隐藏预设清单失败，请重试');
    }
  }

  Future<void> _showIconPicker(TaskList list) async {
    const iconOptions = [
      'list',
      'home',
      'work',
      'book',
      'shopping',
      'health',
      'fitness',
      'finance',
      'travel',
      'idea',
      'project',
      'flag',
      'calendar',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Text('选择清单图标', style: TextStyle(color: context.appColors.text)),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: iconOptions.map((key) {
              final selected = key == list.iconKey;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(dialogContext).pop(key),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? context.appColors.surfaceElevated
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? context.appColors.accent
                          : context.appColors.border,
                    ),
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.taskListIcon(key),
                      color: selected
                          ? context.appColors.accent
                          : context.appColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
    if (selected == null) return;
    try {
      await ref.read(taskProvider.notifier).updateListIcon(list.id, selected);
    } catch (_) {
      _showErrorSnackBar('更新清单图标失败，请重试');
    }
  }

  void _createList() async {
    if (_isCreatingList) return;
    if (_newListController.text.trim().isEmpty) {
      _newListDraft = '';
      _cancelCreatingList();
      return;
    }

    final name = _newListController.text.trim();

    // 先关闭输入框，防止重复创建
    setState(() {
      _isCreatingList = true;
      _showNewList = false;
      _newListController.clear();
      _newListDraft = '';
    });

    // 使用短延迟确保 UI 先更新
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      if (!mounted) return;
      final list = await ref.read(taskProvider.notifier).createList(name);
      if (!mounted) return;
      await ref.read(taskProvider.notifier).setCurrentList(list.id, 'custom');
      widget.onListChanged?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showNewList = true;
        _newListController.text = name;
      });
      _showErrorSnackBar('创建清单失败，请重试');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureInputVisible(_newListKey);
      });
    } finally {
      if (mounted) {
        setState(() => _isCreatingList = false);
      }
    }
  }
}
