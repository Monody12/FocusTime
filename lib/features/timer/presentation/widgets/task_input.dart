import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
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
                      borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkAccent
                            : AppColors.lightAccent,
                        width: 2,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                  onTap: () => setState(() => _showHistory = true),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
              IconButton(
                icon: Icon(
                  _showHistory ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
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
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // My day section
                  if (myDayTasks.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Text(
                        '☀ 我的一天',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    ...myDayTasks.map(
                        (task) => _buildHistoryItem(task.title, '📋', isDark)),
                    if (displayHistory.isNotEmpty)
                      Divider(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                  ],

                  // History section
                  if (displayHistory.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Text(
                        '🕐 最近使用',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    ...displayHistory
                        .map((task) => _buildHistoryItem(task, '🕐', isDark)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String title, String icon, bool isDark) {
    return InkWell(
      onTap: () => _handleSelect(title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDark ? AppColors.darkText : AppColors.lightText,
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
