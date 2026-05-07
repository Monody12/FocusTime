import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/recurrence_utils.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  final String taskId;
  final VoidCallback onClose;

  const TaskDetailPage({
    super.key,
    required this.taskId,
    required this.onClose,
  });

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage>
    with WidgetsBindingObserver {
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TextEditingController _expectedMinutesController;
  late TextEditingController _dueDateController;
  late TextEditingController _dueTimeController;
  String? _dueDate;
  String? _dueTime;
  bool _showRecurrencePicker = false;
  Map<String, dynamic>? _recurrenceConfig;
  bool _todayCompleted = false;
  List<Map<String, dynamic>> _focusSessions = [];

  // FocusNode 用于监听焦点变化，实现鼠标离开自动保存
  late FocusNode _titleFocusNode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleController = TextEditingController();
    _notesController = TextEditingController();
    _expectedMinutesController = TextEditingController();
    _dueDateController = TextEditingController();
    _dueTimeController = TextEditingController();
    _titleFocusNode = FocusNode();
    // 监听标题输入框焦点丢失事件，触发自动保存
    _titleFocusNode.addListener(_onTitleFocusChange);
    _loadTaskData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleFocusNode.removeListener(_onTitleFocusChange);
    _titleFocusNode.dispose();
    _titleController.dispose();
    _notesController.dispose();
    _expectedMinutesController.dispose();
    _dueDateController.dispose();
    _dueTimeController.dispose();
    super.dispose();
  }

  // 标题输入框焦点变化时自动保存
  void _onTitleFocusChange() {
    if (!_titleFocusNode.hasFocus) {
      _saveTitle(widget.taskId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveAllEdits();
    }
  }

  @override
  void didUpdateWidget(TaskDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _loadTaskData();
    }
  }

  void _saveAllEdits() {
    final taskState = ref.read(taskProvider);
    final task = taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task == null) return;

    // Save title if changed
    if (_titleController.text.trim().isNotEmpty && _titleController.text.trim() != task.title) {
      ref.read(taskProvider.notifier).updateTask(widget.taskId, {'title': _titleController.text.trim()});
    }

    // Save notes if changed
    if (_notesController.text.trim() != (task.notes ?? '')) {
      ref.read(taskProvider.notifier).updateTask(widget.taskId, {'notes': _notesController.text.trim()});
    }

    // Save expected minutes if changed
    final mins = int.tryParse(_expectedMinutesController.text);
    if (mins != null && mins != task.expectedMinutes) {
      ref.read(taskProvider.notifier).updateTask(widget.taskId, {'expectedMinutes': mins});
    }
  }

  void _loadTaskData() async {
    final taskState = ref.read(taskProvider);
    final task = taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task != null) {
      _titleController.text = task.title;
      _notesController.text = task.notes ?? '';
      _expectedMinutesController.text = task.expectedMinutes?.toString() ?? '';
      _dueDate = task.dueDate;
      _dueTime = task.dueTime;
      _dueDateController.text = task.dueDate ?? '';
      _dueTimeController.text = task.dueTime ?? '';
      _recurrenceConfig = task.recurrenceConfig;

      // Load recurrence completion
      if (_recurrenceConfig != null) {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final completions = await AppDatabase.getRecurrenceCompletions(widget.taskId);
        setState(() {
          _todayCompleted = completions.any((c) => c['completionDate'] == today);
        });
      }

      // Load focus sessions
      final sessions = await AppDatabase.getSessionsByTaskId(widget.taskId);
      setState(() {
        _focusSessions = sessions;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final task = taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (task == null) {
      return const SizedBox.shrink();
    }

    final sessionUpdateTick = ref.watch(sessionUpdateProvider);

    // Reload sessions when they update
    ref.listen(sessionUpdateProvider, (_, __) {
      _loadTaskData();
    });

    final currentList = taskState.lists.where((l) => l.id == task.listId).firstOrNull;

    return Container(
      width: 320,
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '任务详情',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title with checkbox
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => taskNotifier.toggleTaskComplete(task.id),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: task.completed ? const Color(0xFF7C3AED) : Colors.transparent,
                            border: Border.all(
                              color: task.completed ? const Color(0xFF7C3AED) : AppColors.darkBorder,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: task.completed
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: const Color(0xFF7C3AED),
                              ),
                            ),
                            hintText: '任务标题',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: task.completed ? TextDecoration.lineThrough : null,
                            color: task.completed
                                ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                                : (isDark ? AppColors.darkText : AppColors.lightText),
                          ),
                          maxLines: null,
                          onSubmitted: (_) => _saveTitle(task.id),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // My Day button
                  _buildActionButton(
                    icon: '☀',
                    label: task.isMyDay ? '已添加到"我的一天"' : '添加到"我的一天"',
                    isActive: task.isMyDay,
                    onTap: () {
                      if (task.isMyDay) {
                        taskNotifier.removeFromMyDay(task.id);
                      } else {
                        taskNotifier.addToMyDay(task.id);
                      }
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 8),

                  // Start focus button
                  _buildActionButton(
                    icon: '🎯',
                    label: '开始专注',
                    isActive: false,
                    onTap: () {
                      ref.read(timerProvider.notifier).startFocus(
                            taskTitle: task.title,
                            taskId: task.id,
                          );
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 16),

                  // Due date
                  _buildSectionLabel('截止日期', isDark),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dueDateController,
                          decoration: InputDecoration(
                            hintText: '日期',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          readOnly: true,
                          onTap: () => _selectDueDate(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _dueTimeController,
                          decoration: InputDecoration(
                            hintText: '时间',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          readOnly: true,
                          onTap: () => _selectDueTime(context),
                        ),
                      ),
                      if (_dueDate != null || _dueTime != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _dueDate = null;
                              _dueTime = null;
                              _dueDateController.clear();
                              _dueTimeController.clear();
                            });
                            taskNotifier.updateTask(task.id, {
                              'dueDate': null,
                              'dueTime': null,
                            });
                          },
                          child: const Text('清除'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Expected minutes
                  _buildSectionLabel('预期时间（分钟）', isDark),
                  TextField(
                    controller: _expectedMinutesController,
                    decoration: InputDecoration(
                      hintText: '预计需要的专注时间',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _saveExpectedMinutes(task.id),
                    onEditingComplete: () => _saveExpectedMinutes(task.id),
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  _buildSectionLabel('备注', isDark),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: '添加备注...',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    maxLines: 4,
                    onSubmitted: (_) => _saveNotes(task.id),
                    onEditingComplete: () => _saveNotes(task.id),
                  ),

                  const SizedBox(height: 16),

                  // Recurrence
                  _buildSectionLabel('重复', isDark),
                  if (_recurrenceConfig == null)
                    _buildActionButton(
                      icon: '🔄',
                      label: '设置重复',
                      isActive: false,
                      onTap: () {
                        setState(() => _showRecurrencePicker = true);
                      },
                      isDark: isDark,
                    )
                  else
                    _buildRecurrenceDisplay(task.id, isDark),

                  // Recurrence picker (simplified)
                  if (_showRecurrencePicker) _buildRecurrencePicker(task.id, isDark),

                  const SizedBox(height: 16),

                  // Focus history
                  if (_focusSessions.isNotEmpty) ...[
                    _buildSectionLabel('专注记录', isDark),
                    ..._focusSessions.take(5).map((s) => _buildSessionItem(s, isDark)),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '累计 ${(_focusSessions.fold<int>(0, (sum, s) => sum + (s['durationSeconds'] as int)) / 60).floor()} 分钟 · ${_focusSessions.length} 次',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // List info
                  _buildSectionLabel('所属清单：${currentList?.name ?? '未知'}', isDark),

                  // Delete button
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        taskNotifier.deleteTask(task.id);
                        widget.onClose();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('删除任务'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: isActive
          ? (isDark ? AppColors.darkBackground : AppColors.lightBackground)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _buildRecurrenceDisplay(String taskId, bool isDark) {
    final config = RecurrenceConfig.fromJson(_recurrenceConfig!);
    return Row(
      children: [
        Expanded(
          child: Text(
            '🔄 ${getRecurrenceSummary(config)}',
            style: TextStyle(
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _showRecurrencePicker = true),
          child: const Text('修改'),
        ),
      ],
    );
  }

  Widget _buildRecurrencePicker(String taskId, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设置重复',
            style: TextStyle(
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              _buildRecurrenceChip('每天', () => _setRecurrence(taskId, RecurrenceFrequency.daily)),
              _buildRecurrenceChip('每周', () => _setRecurrence(taskId, RecurrenceFrequency.weekly)),
              _buildRecurrenceChip('每月', () => _setRecurrence(taskId, RecurrenceFrequency.monthly)),
              _buildRecurrenceChip('每年', () => _setRecurrence(taskId, RecurrenceFrequency.yearly)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showRecurrencePicker = false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(taskProvider.notifier).updateTask(taskId, {
                    'recurrenceConfig': null,
                  });
                  setState(() {
                    _showRecurrencePicker = false;
                    _recurrenceConfig = null;
                  });
                },
                child: const Text('清除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecurrenceChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }

  void _setRecurrence(String taskId, RecurrenceFrequency frequency) async {
    final config = RecurrenceConfig(frequency: frequency, interval: 1);
    await ref.read(taskProvider.notifier).updateTask(taskId, {
      'recurrenceConfig': config.toJson(),
    });
    setState(() {
      _recurrenceConfig = config.toJson();
      _showRecurrencePicker = false;
    });
  }

  Widget _buildSessionItem(Map<String, dynamic> session, bool isDark) {
    final startedAt = DateTime.fromMillisecondsSinceEpoch(session['startedAt'] as int);
    final dateStr = '${startedAt.month}/${startedAt.day}';
    final timeStr = '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    final mins = ((session['durationSeconds'] as int) / 60).floor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$dateStr $timeStr',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${mins}分钟',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            session['completed'] == true ? '✓' : '○',
            style: TextStyle(
              fontSize: 12,
              color: (session['completed'] == true)
                  ? AppColors.darkSuccess
                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _selectDueDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate != null ? DateTime.parse(_dueDate!) : DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      setState(() {
        _dueDate = dateStr;
        _dueDateController.text = dateStr;
      });
      ref.read(taskProvider.notifier).updateTask(widget.taskId, {'dueDate': _dueDate});
    }
  }

  void _selectDueTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _dueTime != null
          ? TimeOfDay(hour: int.parse(_dueTime!.split(':')[0]), minute: int.parse(_dueTime!.split(':')[1]))
          : TimeOfDay.now(),
    );
    if (time != null) {
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      setState(() {
        _dueTime = timeStr;
        _dueTimeController.text = timeStr;
      });
      ref.read(taskProvider.notifier).updateTask(widget.taskId, {'dueTime': _dueTime});
    }
  }

  void _saveTitle(String taskId) {
    if (_titleController.text.trim().isNotEmpty) {
      ref.read(taskProvider.notifier).updateTask(taskId, {'title': _titleController.text.trim()});
    }
  }

  void _saveNotes(String taskId) {
    ref.read(taskProvider.notifier).updateTask(taskId, {'notes': _notesController.text.trim()});
  }

  void _saveExpectedMinutes(String taskId) {
    final mins = int.tryParse(_expectedMinutesController.text);
    ref.read(taskProvider.notifier).updateTask(taskId, {'expectedMinutes': mins});
  }
}
