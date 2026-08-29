import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/features/tasks/presentation/widgets/task_item.dart';

extension on TaskSortMode {
  String get label => switch (this) {
    TaskSortMode.manual => '手动排序',
    TaskSortMode.createdAscending => '创建时间（升序）',
    TaskSortMode.createdDescending => '创建时间（降序）',
    TaskSortMode.updatedAscending => '最后修改时间（升序）',
    TaskSortMode.updatedDescending => '最后修改时间（降序）',
    TaskSortMode.titleAscending => '任务名称（升序）',
    TaskSortMode.titleDescending => '任务名称（降序）',
    TaskSortMode.dueDateAscending => '截止日期（升序）',
    TaskSortMode.dueDateDescending => '截止日期（降序）',
  };
}

class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({super.key});

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  final _newTaskController = TextEditingController();
  final Set<String> _expandedCompletedListIds = {};

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

    final incompleteTasks = sortTaskItems(
      taskState.tasks.where((task) => !task.completed),
      taskState.sortMode,
    );
    final completedTasks = sortTaskItems(
      taskState.tasks.where((task) => task.completed),
      taskState.sortMode,
    );
    final completedExpanded = _expandedCompletedListIds.contains(
      taskState.currentListId,
    );

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
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        listName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.appColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${incompleteTasks.length} 个未完成',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<TaskSortMode>(
                tooltip: '排序：${taskState.sortMode.label}',
                initialValue: taskState.sortMode,
                onSelected: taskNotifier.setSortMode,
                icon: AppIcon(
                  AppIcons.sort,
                  size: AppIconSizes.action,
                  color: context.appColors.text,
                ),
                itemBuilder: (context) => TaskSortMode.values
                    .map(
                      (mode) => CheckedPopupMenuItem<TaskSortMode>(
                        value: mode,
                        checked: mode == taskState.sortMode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),

        // Add task input
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.appColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.appColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: AppIconSizes.action,
                height: AppIconSizes.action,
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.addTask,
                  size: AppIconSizes.action,
                  color: context.appColors.accentSecondary,
                ),
              ),
              const SizedBox(width: AppIconSpacing.labelGap),
              Expanded(
                child: TextField(
                  controller: _newTaskController,
                  decoration: InputDecoration(
                    hintText: '添加任务...',
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  style: TextStyle(fontSize: 14, color: context.appColors.text),
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
              : RefreshIndicator(
                  onRefresh: _syncNow,
                  child: taskState.tasks.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.45,
                              child: _buildEmptyState(isDark),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            // Incomplete tasks
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              // 由 TaskItemWidget 内的 ReorderableDragStartListener 接管拖拽
                              buildDefaultDragHandles: false,
                              onReorderItem: (oldIndex, newIndex) async {
                                final taskIds = incompleteTasks
                                    .map((t) => t.id)
                                    .toList();
                                final item = taskIds.removeAt(oldIndex);
                                taskIds.insert(newIndex, item);
                                try {
                                  await taskNotifier.reorderTasks(taskIds);
                                  taskNotifier.setSortMode(TaskSortMode.manual);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('任务排序失败，请重试')),
                                  );
                                }
                              },
                              children: [
                                for (int i = 0; i < incompleteTasks.length; i++)
                                  TaskItemWidget(
                                    key: ValueKey(incompleteTasks[i].id),
                                    task: incompleteTasks[i],
                                    index: i,
                                    isSelected:
                                        taskState.selectedTaskId ==
                                        incompleteTasks[i].id,
                                    onTap: () {
                                      taskNotifier.setSelectedTask(
                                        incompleteTasks[i].id,
                                      );
                                    },
                                  ),
                              ],
                            ),

                            // Completed tasks
                            if (completedTasks.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                key: const ValueKey('completed_header'),
                                onTap: () {
                                  setState(() {
                                    if (completedExpanded) {
                                      _expandedCompletedListIds.remove(
                                        taskState.currentListId,
                                      );
                                    } else {
                                      _expandedCompletedListIds.add(
                                        taskState.currentListId,
                                      );
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      AppIcon(
                                        completedExpanded
                                            ? AppIcons.expandLess
                                            : AppIcons.expandMore,
                                        size: AppIconSizes.compact,
                                        color: context.appColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '已完成 (${completedTasks.length})',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              context.appColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (completedExpanded)
                                for (int i = 0; i < completedTasks.length; i++)
                                  TaskItemWidget(
                                    key: ValueKey(completedTasks[i].id),
                                    task: completedTasks[i],
                                    isSelected:
                                        taskState.selectedTaskId ==
                                        completedTasks[i].id,
                                    onTap: () {
                                      taskNotifier.setSelectedTask(
                                        completedTasks[i].id,
                                      );
                                    },
                                  ),
                            ],
                          ],
                        ),
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
          AppIcon(
            AppIcons.emptyTasks,
            size: AppIconSizes.empty,
            color: context.appColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有任务，添加一个吧',
            style: TextStyle(
              fontSize: 16,
              color: context.appColors.textSecondary,
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
      await ref
          .read(taskProvider.notifier)
          .createTask(_newTaskController.text.trim(), isMyDay: isMyDay);
      _newTaskController.clear();
    }
  }

  Future<void> _syncNow() async {
    final result = await ref.read(taskProvider.notifier).sync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.success ? '同步完成' : '同步失败，请检查登录和网络')),
    );
  }
}
