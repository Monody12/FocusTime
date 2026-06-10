import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';

class TaskInput extends ConsumerStatefulWidget {
  const TaskInput({super.key});

  @override
  ConsumerState<TaskInput> createState() => _TaskInputState();
}

class _TaskInputState extends ConsumerState<TaskInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _showHistory = false;
  List<String> _localHistory = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Force rebuild if needed
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final timerState = ref.watch(timerProvider);

    // Get my day tasks
    final myDayTasks =
        taskState.tasks.where((t) => t.isMyDay && !t.completed).toList();

    // Sync local history with timer state history
    final displayHistory = timerState.taskHistory.isNotEmpty
        ? timerState.taskHistory
        : _localHistory;

    // Combine my day tasks with history
    final showDropdown =
        _showHistory && (myDayTasks.isNotEmpty || displayHistory.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前专注：',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: '输入你正在专注的内容...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.appColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.appColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: context.appColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    color: context.appColors.text,
                  ),
                  onTap: () => setState(() => _showHistory = true),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
              IconButton(
                icon: Icon(
                  _showHistory ? AppIcons.expandLess : AppIcons.expandMore,
                  color: context.appColors.textSecondary,
                ),
                onPressed: () => setState(() => _showHistory = !_showHistory),
              ),
            ],
          ),

          // History dropdown
          if (showDropdown)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.appColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // My day section
                  if (myDayTasks.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          AppIcon(
                            AppIcons.myDay,
                            size: AppIconSizes.status,
                            color: context.appColors.textSecondary,
                          ),
                          const SizedBox(width: AppIconSpacing.compactGap),
                          Text(
                            '我的一天',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...myDayTasks.map((task) =>
                        _buildHistoryItem(task.title, AppIcons.tasks)),
                    if (displayHistory.isNotEmpty)
                      Divider(color: context.appColors.border),
                  ],

                  // History section
                  if (displayHistory.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          AppIcon(
                            AppIcons.recent,
                            size: AppIconSizes.status,
                            color: context.appColors.textSecondary,
                          ),
                          const SizedBox(width: AppIconSpacing.compactGap),
                          Text(
                            '最近使用',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...displayHistory.map(
                        (task) => _buildHistoryItem(task, AppIcons.recent)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String title, IconData icon) {
    return InkWell(
      onTap: () => _handleSelect(title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: AppIconSizes.status,
              color: context.appColors.textSecondary,
            ),
            const SizedBox(width: AppIconSpacing.compactGap),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: context.appColors.text,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSelect(String title) {
    _controller.text = title;
    ref.read(timerProvider.notifier).setCurrentTask(title);
    // Local history is synced via TimerState, no need to maintain separate state
    setState(() => _showHistory = false);
  }

  void _handleSubmit() {
    if (_controller.text.trim().isNotEmpty) {
      ref.read(timerProvider.notifier).setCurrentTask(_controller.text.trim());
    }
    setState(() => _showHistory = false);
    _focusNode.unfocus();
  }
}
