import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/task_provider.dart';

class TaskItemWidget extends ConsumerStatefulWidget {
  final TaskItem task;
  final bool isSelected;
  // 当在 ReorderableListView 中时提供此 index，用于鼠标拖动排序
  final int? index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const TaskItemWidget({
    super.key,
    required this.task,
    required this.isSelected,
    this.index,
    required this.onTap,
    this.onLongPress,
  });

  @override
  ConsumerState<TaskItemWidget> createState() => _TaskItemWidgetState();
}

class _TaskItemWidgetState extends ConsumerState<TaskItemWidget> {
  // 拖拽状态标志：防止拖拽过程中或刚结束（动画未完成）时误触发点击事件
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = _isOverdue(widget.task.dueDate);

    // 任务项内容 widget
    final Widget content = GestureDetector(
      // 拖拽状态时禁用点击，防止误触发（长按后即使没移动也会触发 drag）
      onTap: _isDragging ? null : widget.onTap,
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? (isDark ? const Color(0xFF3D3D5C) : const Color(0xFFE5E7EB))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // 复选框
            GestureDetector(
              onTap: () => taskNotifier.toggleTaskComplete(widget.task.id),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.task.completed
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.task.completed
                        ? const Color(0xFF7C3AED)
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: widget.task.completed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // 任务标题
            Expanded(
              child: Text(
                widget.task.title,
                style: TextStyle(
                  fontSize: 15,
                  color: widget.task.completed
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                      : isOverdue && !widget.task.completed
                          ? Colors.red
                          : (isDark ? AppColors.darkText : AppColors.lightText),
                  decoration: widget.task.completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            // 我的一天图标
            if (widget.task.isMyDay)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.wb_sunny_outlined,
                  size: 16,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            // 重要图标
            if (widget.task.isImportant)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: const Icon(
                  Icons.star,
                  size: 16,
                  color: Color(0xFF7C3AED),
                ),
              ),
            // 截止日期
            if (widget.task.dueDate != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: isOverdue && !widget.task.completed
                          ? Colors.red
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatDueDate(widget.task.dueDate!),
                      style: TextStyle(
                        fontSize: 12,
                        color: isOverdue && !widget.task.completed
                            ? Colors.red
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    // 长按拖拽：用于将任务移动到其他清单
    final draggable = LongPressDraggable<String>(
      data: widget.task.id,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF7C3AED),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.task.completed
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.task.completed
                        ? const Color(0xFF7C3AED)
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: widget.task.completed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.task.title,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: content,
      ),
      onDragStarted: () {
        setState(() => _isDragging = true);
      },
      onDragEnd: (details) {
        setState(() => _isDragging = false);
      },
      onDraggableCanceled: (velocity, offset) {
        setState(() => _isDragging = false);
      },
      child: content,
    );

    // 当在 ReorderableListView 中时，用 ReorderableDragStartListener 包裹整个 item
    // 鼠标按住即可拖动排序（无需专门手柄），长按依然触发跨清单拖拽
    if (widget.index != null) {
      return ReorderableDragStartListener(
        index: widget.index!,
        child: draggable,
      );
    }

    return draggable;
  }

  bool _isOverdue(String? dueDate) {
    if (dueDate == null) return false;
    try {
      final today = DateTime.now();
      final due = DateTime.parse(dueDate);
      return due.isBefore(DateTime(today.year, today.month, today.day));
    } catch (_) {
      return false;
    }
  }

  String _formatDueDate(String dueDate) {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

    if (dueDate == todayStr) return '今天';
    if (dueDate == tomorrowStr) return '明天';
    return dueDate;
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? const Color(0xFF2D2D3F) : Colors.white,
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () {
            if (widget.task.isMyDay) {
              taskNotifier.removeFromMyDay(widget.task.id);
            } else {
              taskNotifier.addToMyDay(widget.task.id);
            }
          },
          child: _buildMenuItem(
            widget.task.isMyDay ? Icons.wb_sunny : Icons.wb_sunny_outlined,
            widget.task.isMyDay ? '从"我的一天"中移除' : '添加到"我的一天"',
            'Ctrl+T',
            isDark,
          ),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => taskNotifier.toggleTaskImportant(widget.task.id),
          child: _buildMenuItem(
            widget.task.isImportant ? Icons.star : Icons.star_border,
            widget.task.isImportant ? '取消标记为重要' : '标记为重要',
            null,
            isDark,
          ),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => taskNotifier.toggleTaskComplete(widget.task.id),
          child: _buildMenuItem(
            widget.task.completed ? Icons.check_circle : Icons.radio_button_unchecked,
            widget.task.completed ? '标记为未完成' : '标记为已完成',
            'Ctrl+D',
            isDark,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<dynamic>(
          height: 38,
          enabled: false,
          child: Text(
            '到期日',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => _setDueDate(DateTime.now()),
          child: _buildMenuItem(Icons.event, '今天', null, isDark),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => _setDueDate(DateTime.now().add(const Duration(days: 1))),
          child: _buildMenuItem(Icons.event_note, '明天', null, isDark),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => _pickDate(context),
          child: _buildMenuItem(Icons.calendar_today, '选择日期', null, isDark),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => Future.delayed(Duration.zero, () => _showMoveToDialog(context)),
          child: _buildMenuItem(Icons.move_to_inbox, '移动任务到...', null, isDark),
        ),
        PopupMenuItem<dynamic>(
          height: 38,
          onTap: () => Future.delayed(Duration.zero, () => _confirmDelete(context)),
          child: _buildMenuItem(Icons.delete_outline, '删除任务', 'Delete', isDark, isDanger: true),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务', style: TextStyle(fontSize: 16)),
        content: Text('确定要删除任务 "${widget.task.title}" 吗？'),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(taskProvider.notifier).deleteTask(widget.task.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showMoveToDialog(BuildContext context) {
    final taskState = ref.read(taskProvider);
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 排除系统清单和当前清单
    final otherLists = taskState.lists.where((l) => !l.isSystem && l.id != widget.task.listId).toList();

    if (otherLists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有其他可移动的清单')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动任务到', style: TextStyle(fontSize: 16)),
        backgroundColor: isDark ? const Color(0xFF2D2D3F) : Colors.white,
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherLists.length,
            itemBuilder: (context, index) {
              final list = otherLists[index];
              return ListTile(
                title: Text(list.name),
                leading: const Icon(Icons.list),
                onTap: () {
                  taskNotifier.moveTaskToList(widget.task.id, list.id);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String text, String? shortcut, bool isDark, {bool isDanger = false}) {
    final color = isDanger ? Colors.red : (isDark ? Colors.white : Colors.black87);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
        if (shortcut != null)
          Text(
            shortcut,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
      ],
    );
  }

  void _setDueDate(DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    ref.read(taskProvider.notifier).updateTask(widget.task.id, {'dueDate': dateStr});
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.task.dueDate != null ? DateTime.parse(widget.task.dueDate!) : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _setDueDate(picked);
    }
  }
}