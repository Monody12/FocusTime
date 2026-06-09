import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/features/tasks/presentation/widgets/task_item.dart';

class TaskListView extends ConsumerStatefulWidget {
  final Function(String?)? onTaskSelected;

  const TaskListView({super.key, this.onTaskSelected});

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  final _newTaskController = TextEditingController();

  @override
  void dispose() {
    _newTaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final incompleteTasks = taskState.tasks.where((t) => !t.completed).toList();
    final completedTasks = taskState.tasks.where((t) => t.completed).toList();

    String listName;
    if (taskState.currentViewType == 'my-day') {
      listName = '我的一天';
    } else if (taskState.currentViewType == 'all-tasks') {
      listName = '任务';
    } else {
      final currentList = taskState.lists
          .where((l) => l.id == taskState.currentListId)
          .firstOrNull;
      listName = currentList?.name ?? '清单';
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Row(
            children: [
              Text(
                listName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${incompleteTasks.length} 个未完成',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),

        // Add task input
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                isDark ? AppColors.darkSurface : AppColors.lightSurfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.14 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 18,
                    color: isDark
                        ? AppColors.darkAccentSecondary
                        : AppColors.lightAccentSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _newTaskController,
                  decoration: InputDecoration(
                    hintText: '添加任务...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                  onSubmitted: (_) => _addTask(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Task list
        Expanded(
          child: taskState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : taskState.tasks.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView(
                      children: [
                        // Incomplete tasks
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          // 由 TaskItemWidget 内的 ReorderableDragStartListener 接管拖拽
                          buildDefaultDragHandles: false,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final taskIds =
                                incompleteTasks.map((t) => t.id).toList();
                            final item = taskIds.removeAt(oldIndex);
                            taskIds.insert(newIndex, item);
                            taskNotifier.reorderTasks(taskIds);
                          },
                          children: [
                            for (int i = 0; i < incompleteTasks.length; i++)
                              TaskItemWidget(
                                key: ValueKey(incompleteTasks[i].id),
                                task: incompleteTasks[i],
                                index: i,
                                isSelected: taskState.selectedTaskId ==
                                    incompleteTasks[i].id,
                                onTap: () {
                                  taskNotifier
                                      .setSelectedTask(incompleteTasks[i].id);
                                  widget.onTaskSelected
                                      ?.call(incompleteTasks[i].id);
                                },
                              ),
                          ],
                        ),

                        // Completed tasks
                        if (completedTasks.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            key: const ValueKey('completed_header'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Text(
                                  '已完成 (${completedTasks.length})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (int i = 0; i < completedTasks.length; i++)
                            TaskItemWidget(
                              key: ValueKey(completedTasks[i].id),
                              task: completedTasks[i],
                              isSelected: taskState.selectedTaskId ==
                                  completedTasks[i].id,
                              onTap: () {
                                taskNotifier
                                    .setSelectedTask(completedTasks[i].id);
                                widget.onTaskSelected
                                    ?.call(completedTasks[i].id);
                              },
                            ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '📝',
            style: TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有任务，添加一个吧',
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _addTask() async {
    if (_newTaskController.text.trim().isNotEmpty) {
      final currentViewType = ref.read(taskProvider).currentViewType;
      final isMyDay = currentViewType == 'my-day';
      await ref.read(taskProvider.notifier).createTask(
            _newTaskController.text.trim(),
            isMyDay: isMyDay,
          );
      _newTaskController.clear();
    }
  }
}
