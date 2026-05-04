import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/task_provider.dart';

class TaskItemWidget extends ConsumerStatefulWidget {
  final TaskItem task;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const TaskItemWidget({
    super.key,
    required this.task,
    required this.isSelected,
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
                child: Text(
                  '☀',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
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
    return LongPressDraggable<String>(
      data: widget.task.id,
      delay: const Duration(milliseconds: 200),
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
}