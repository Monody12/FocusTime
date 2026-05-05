import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../tasks/providers/task_provider.dart';

class Sidebar extends ConsumerStatefulWidget {
  final VoidCallback? onListChanged;

  const Sidebar({super.key, this.onListChanged});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _showNewList = false;
  final _newListController = TextEditingController();
  String? _editingListId;
  final _editController = TextEditingController();
  String? _dragHoverListId;

  // FocusNode 用于监听新建清单输入框的失焦事件
  late FocusNode _newListFocusNode;

  @override
  void initState() {
    super.initState();
    _newListFocusNode = FocusNode();
    // 监听新建清单输入框的失焦事件：空内容时还原状态，有内容时创建清单
    _newListFocusNode.addListener(_onNewListFocusChange);
  }

  @override
  void dispose() {
    _newListFocusNode.removeListener(_onNewListFocusChange);
    _newListFocusNode.dispose();
    _newListController.dispose();
    _editController.dispose();
    super.dispose();
  }

  // 新建清单输入框失焦时的处理逻辑
  void _onNewListFocusChange() {
    if (!_newListFocusNode.hasFocus && _showNewList) {
      // 失焦时检查是否有内容
      if (_newListController.text.trim().isNotEmpty) {
        _createList();
      } else {
        // 空内容则还原为未点击状态
        setState(() {
          _showNewList = false;
          _newListController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final systemLists = taskState.lists.where((l) => l.isSystem).toList();
    final customLists = taskState.lists.where((l) => !l.isSystem).toList();

    return Container(
      width: 220,
      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildListItem(
                  context,
                  icon: '☀',
                  label: '我的一天',
                  isSelected: taskState.currentListId == 'system-my-day',
                  onTap: () {
                    taskNotifier.setCurrentList('system-my-day', 'my-day');
                    widget.onListChanged?.call();
                  },
                  isDark: isDark,
                ),
                _buildListItem(
                  context,
                  icon: '⭐',
                  label: '重要',
                  isSelected: taskState.currentListId == 'system-important',
                  onTap: () {
                    taskNotifier.setCurrentList('system-important', 'important');
                    widget.onListChanged?.call();
                  },
                  isDark: isDark,
                ),
                _buildListItem(
                  context,
                  icon: '📋',
                  label: '任务',
                  isSelected: taskState.currentListId == 'system-all-tasks',
                  onTap: () {
                    taskNotifier.setCurrentList('system-all-tasks', 'all-tasks');
                    widget.onListChanged?.call();
                  },
                  isDark: isDark,
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '清单',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),

                // Custom lists (as drop targets for task drag-and-drop)
                ...customLists.map((list) {
                  if (_editingListId == list.id) {
                    return _buildEditingItem(list.id, list.name, isDark);
                  }
                  return _buildDraggableListItem(
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
                      await taskNotifier.updateTask(taskId, {'listId': list.id});
                      widget.onListChanged?.call();
                    },
                    onLongPress: () => _showListMenu(context, list.id, list.name),
                    isDark: isDark,
                  );
                }),

                // New list input
                if (_showNewList)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _newListController,
                      focusNode: _newListFocusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '清单名称...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) => _createList(),
                      onEditingComplete: _createList,
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
    required String icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required bool isDark,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Material(
        color: isSelected
            ? (isDark ? AppColors.darkSurface : AppColors.lightSurface)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? (isDark ? AppColors.darkText : AppColors.lightText)
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

  // 自定义清单项（可作为拖拽目标接收任务）
  Widget _buildDraggableListItem(
    BuildContext context, {
    required TaskList list,
    required bool isSelected,
    required bool isHovering,
    required VoidCallback onTap,
    required Function(bool) onHover,
    required Function(String) onAccept,
    VoidCallback? onLongPress,
    required bool isDark,
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
          onLongPress: onLongPress,
          onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, list.id, list.name),
          child: Material(
            color: isHovering
                ? (isDark ? const Color(0xFF3D3D5C) : const Color(0xFFE5E7EB))
                : isSelected
                    ? (isDark ? AppColors.darkSurface : AppColors.lightSurface)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text('📁', style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        list.name,
                        style: TextStyle(
                          color: isSelected
                              ? (isDark ? AppColors.darkText : AppColors.lightText)
                              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isHovering)
                      Icon(
                        Icons.add_circle,
                        size: 18,
                        color: const Color(0xFF7C3AED),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _editController,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onSubmitted: (_) => _renameList(listId),
      ),
    );
  }

  /// 显示右键菜单（适用于桌面端）
  void _showContextMenu(BuildContext context, Offset globalPosition, String listId, String listName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 获取 Overlay 的 RenderBox 以计算相对位置
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40), // 在点击位置周围创建一个小的矩形区域
        Offset.zero & overlay.size,
      ),
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'rename',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: isDark ? AppColors.darkText : AppColors.lightText),
              const SizedBox(width: 12),
              Text('重命名', style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkText : AppColors.lightText)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              const SizedBox(width: 12),
              const Text('删除', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'rename') {
        _startEditing(listId, listName);
      } else if (value == 'delete') {
        _confirmDeleteList(context, listId, listName);
      }
    });
  }

  // 新建清单按钮
  Widget _buildAddButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _showNewList = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.add,
                size: 20,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                '新建清单',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showListMenu(BuildContext context, String listId, String listName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  listName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(context);
                  _startEditing(listId, listName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteList(context, listId, listName);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteList(BuildContext context, String listId, String listName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          title: Text(
            '删除清单',
            style: TextStyle(color: isDark ? AppColors.darkText : AppColors.lightText),
          ),
          content: Text(
            '确定要删除 "$listName" 吗？该清单下的所有任务也会被删除。',
            style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
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
  }

  void _renameList(String listId) async {
    if (_editController.text.trim().isNotEmpty) {
      await ref.read(taskProvider.notifier).updateList(listId, _editController.text.trim());
    }
    setState(() {
      _editingListId = null;
      _editController.clear();
    });
  }

  void _deleteList(String listId) async {
    await ref.read(taskProvider.notifier).deleteList(listId);
    final taskState = ref.read(taskProvider);
    if (taskState.currentListId == listId) {
      await ref.read(taskProvider.notifier).setCurrentList('system-my-day', 'my-day');
    }
    widget.onListChanged?.call();
  }

  void _createList() async {
    if (_newListController.text.trim().isEmpty) {
      setState(() {
        _showNewList = false;
        _newListController.clear();
      });
      return;
    }

    final name = _newListController.text.trim();

    // 先关闭输入框，防止重复创建
    setState(() {
      _showNewList = false;
      _newListController.clear();
    });

    // 使用短延迟确保 UI 先更新
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;
    final list = await ref.read(taskProvider.notifier).createList(name);
    if (!mounted) return;
    await ref.read(taskProvider.notifier).setCurrentList(list.id, 'custom');
    widget.onListChanged?.call();
  }
}