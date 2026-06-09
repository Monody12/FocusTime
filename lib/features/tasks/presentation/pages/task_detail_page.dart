import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';
import 'package:focus_my_time/features/calendar/services/calendar_service.dart';

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
  TaskItem? _cachedTask;

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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
    final task =
        taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task == null) return;

    // Save title if changed
    if (_titleController.text.trim().isNotEmpty &&
        _titleController.text.trim() != task.title) {
      ref
          .read(taskProvider.notifier)
          .updateTask(widget.taskId, {'title': _titleController.text.trim()});
    }

    // Save notes if changed
    if (_notesController.text.trim() != (task.notes ?? '')) {
      ref
          .read(taskProvider.notifier)
          .updateTask(widget.taskId, {'notes': _notesController.text.trim()});
    }

    // Save expected minutes if changed
    final mins = int.tryParse(_expectedMinutesController.text);
    if (mins != null && mins != task.expectedMinutes) {
      ref
          .read(taskProvider.notifier)
          .updateTask(widget.taskId, {'expectedMinutes': mins});
    }
  }

  void _loadTaskData() async {
    final taskState = ref.read(taskProvider);
    TaskItem? task =
        taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull;

    // 如果在当前视图状态中找不到任务（可能是切换了列表），则从数据库加载
    if (task == null) {
      final dbTask = await AppDatabase.getTaskById(widget.taskId);
      if (dbTask != null) {
        task = TaskItem(
          id: dbTask['id'] as String,
          listId: dbTask['listId'] as String,
          title: dbTask['title'] as String,
          notes: dbTask['notes'] as String?,
          completed: dbTask['completed'] == true,
          completedAt: dbTask['completedAt'] as int?,
          dueDate: dbTask['dueDate'] as String?,
          dueTime: dbTask['dueTime'] as String?,
          sortOrder: dbTask['sortOrder'] as int,
          isMyDay: dbTask['isMyDay'] == true,
          myDayAddedAt: dbTask['myDayAddedAt'] as int?,
          recurrenceConfig: dbTask['recurrenceConfig'] as Map<String, dynamic>?,
          expectedMinutes: dbTask['expectedMinutes'] as int?,
          isImportant: dbTask['isImportant'] == true,
          reminderAt: dbTask['reminderAt'] as int?,
          createdAt: dbTask['createdAt'] as int,
          updatedAt: dbTask['updatedAt'] as int,
        );
      }
    }

    if (task != null && mounted) {
      final currentTask = task;
      setState(() {
        _cachedTask = currentTask;
        _titleController.text = currentTask.title;
        _notesController.text = currentTask.notes ?? '';
        _expectedMinutesController.text =
            currentTask.expectedMinutes?.toString() ?? '';
        _dueDate = currentTask.dueDate;
        _dueTime = currentTask.dueTime;
        _dueDateController.text = currentTask.dueDate ?? '';
        _dueTimeController.text = currentTask.dueTime ?? '';
        _recurrenceConfig = currentTask.recurrenceConfig;
      });

      // Load recurrence completion
      if (_recurrenceConfig != null) {
        final today = AppTime.formatDate(AppTime.now());
        final completions =
            await AppDatabase.getRecurrenceCompletions(widget.taskId);
        if (mounted) {
          setState(() {
            _todayCompleted =
                completions.any((c) => c['completionDate'] == today);
          });
        }
      }

      // Load focus sessions
      final sessions = await AppDatabase.getSessionsByTaskId(widget.taskId);
      if (mounted) {
        setState(() {
          _focusSessions = sessions;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    // 优先从当前 state.tasks 中获取最新数据，如果没有则使用缓存的数据
    final task =
        taskState.tasks.where((t) => t.id == widget.taskId).firstOrNull ??
            _cachedTask;
    final taskNotifier = ref.read(taskProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (task == null) {
      return Container(
        color: context.appColors.background,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Watch sessionUpdateProvider to trigger rebuild when it changes
    ref.watch(sessionUpdateProvider);
    // Reload sessions when they update
    ref.listen(sessionUpdateProvider, (_, __) {
      _loadTaskData();
    });

    final currentList =
        taskState.lists.where((l) => l.id == task.listId).firstOrNull;

    return Container(
      width: 320,
      color: context.appColors.surface,
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
                            color: task.completed
                                ? (context.appColors.accent)
                                : Colors.transparent,
                            border: Border.all(
                              color: task.completed
                                  ? (context.appColors.accent)
                                  : context.appColors.border,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: task.completed
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
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
                                color: context.appColors.border,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: context.appColors.accent,
                              ),
                            ),
                            hintText: '任务标题',
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: task.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.completed
                                ? (context.appColors.textSecondary)
                                : (context.appColors.text),
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

                  // Reminder
                  _buildSectionLabel('提醒我', isDark),
                  _buildReminderRow(task, isDark),

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
                  if (_showRecurrencePicker)
                    _buildRecurrencePicker(task.id, isDark),

                  const SizedBox(height: 16),

                  // Focus history
                  if (_focusSessions.isNotEmpty) ...[
                    _buildSectionLabel('专注记录', isDark),
                    ..._focusSessions
                        .take(5)
                        .map((s) => _buildSessionItem(s, isDark)),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '累计 ${(_focusSessions.fold<int>(0, (sum, s) => sum + (s['durationSeconds'] as int)) / 60).floor()} 分钟 · ${_focusSessions.length} 次',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // List info
                  _buildSectionLabel(
                      '所属清单：${currentList?.name ?? '未知'}', isDark),

                  const SizedBox(height: 16),

                  // Task timestamps
                  _buildTimestampInfo(task, isDark),

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
      color: isActive ? (context.appColors.background) : Colors.transparent,
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
                    color: context.appColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderRow(TaskItem task, bool isDark) {
    final hasReminder = task.reminderAt != null;
    final isPast =
        hasReminder && task.reminderAt! < DateTime.now().millisecondsSinceEpoch;
    final reminderText = hasReminder
        ? AppTime.formatDateTimeFromMilliseconds(task.reminderAt!)
            .replaceAll('-', '/')
        : '设置提醒时间';

    // 如果过期且未完成，显示为红色；如果已设置但未过期，显示为紫色(Accent)以提供视觉反馈
    final textColor = (isPast && !task.completed)
        ? Colors.red
        : (hasReminder
            ? (context.appColors.accent)
            : (context.appColors.textSecondary));

    return InkWell(
      onTap: () => _showReminderPresets(task),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.appColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasReminder
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              size: 18,
              color: hasReminder
                  ? (context.appColors.accent)
                  : (context.appColors.textSecondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reminderText,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ),
            if (hasReminder)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    ref.read(taskProvider.notifier).setReminder(task.id, null),
              ),
          ],
        ),
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.appColors.background,
        title: Text('未开启提醒权限', style: TextStyle(color: context.appColors.text)),
        content: Text('为了确保提醒能正常送达，请至少开启系统通知或日历同步权限中的一项。',
            style: TextStyle(color: context.appColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ReminderService.requestNotificationPermission();
            },
            child: const Text('请求通知权限'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await CalendarService.setEnabled(true);
              await CalendarService.triggerTestSync();
            },
            child: const Text('请求日历权限'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showReminderPresets(TaskItem task) async {
    final hasAny = await ReminderService.hasAnyReminderPermission();
    if (!hasAny) {
      if (mounted) _showPermissionDialog();
      return;
    }

    final now = AppTime.now();
    // 捕获页面级的 context 和 Navigator，避免在异步操作或弹窗关闭后 context 失效
    final pageContext = context;
    final taskNotifier = ref.read(taskProvider.notifier);

    if (!mounted) return;

    showModalBottomSheet(
      context: pageContext,
      backgroundColor: context.appColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('设置提醒',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            _buildPresetItem(
              sheetContext,
              icon: Icons.access_time,
              label: '今天晚些时候',
              time: '18:00',
              onTap: () {
                final target = AppTime.create(now.year, now.month, now.day, 18);
                if (target.isAfter(now)) {
                  taskNotifier.setReminder(task.id, target);
                } else {
                  taskNotifier.setReminder(
                      task.id, now.add(const Duration(hours: 1)));
                }
                Navigator.pop(sheetContext);
              },
            ),
            _buildPresetItem(
              sheetContext,
              icon: Icons.wb_sunny_outlined,
              label: '明天上午',
              time: '09:00',
              onTap: () {
                final target =
                    AppTime.create(now.year, now.month, now.day + 1, 9);
                taskNotifier.setReminder(task.id, target);
                Navigator.pop(sheetContext);
              },
            ),
            _buildPresetItem(
              sheetContext,
              icon: Icons.next_week_outlined,
              label: '下周一',
              time: '09:00',
              onTap: () {
                int daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
                if (daysUntilMonday == 0) daysUntilMonday = 7;
                final target = AppTime.create(
                    now.year, now.month, now.day + daysUntilMonday, 9);
                taskNotifier.setReminder(task.id, target);
                Navigator.pop(sheetContext);
              },
            ),
            const Divider(),
            _buildPresetItem(
              sheetContext,
              icon: Icons.calendar_today,
              label: '选择日期和时间',
              onTap: () async {
                // 先关闭底部菜单
                Navigator.pop(sheetContext);

                // 使用页面级的 context 弹出日期选择器
                final date = await showDatePicker(
                  context: pageContext,
                  initialDate: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );

                if (date != null && pageContext.mounted) {
                  // 使用页面级的 context 弹出时间选择器
                  final time = await showTimePicker(
                    context: pageContext,
                    initialTime: TimeOfDay.fromDateTime(
                        now.add(const Duration(hours: 1))),
                  );

                  if (time != null) {
                    final target = AppTime.create(date.year, date.month,
                        date.day, time.hour, time.minute);
                    taskNotifier.setReminder(task.id, target);
                  }
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetItem(BuildContext context,
      {required IconData icon,
      required String label,
      String? time,
      required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(
        icon,
        color: context.appColors.accent,
      ),
      title: Text(label),
      trailing: time != null
          ? Text(time, style: TextStyle(color: context.appColors.textSecondary))
          : null,
      onTap: onTap,
    );
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.appColors.textSecondary,
        ),
      ),
    );
  }

  /// 格式化 Unix 毫秒时间戳为可读日期时间字符串
  String _formatTimestamp(int milliseconds) {
    return AppTime.formatDateTimeFromMilliseconds(milliseconds)
        .replaceAll('-', '/');
  }

  Widget _buildTimestampInfo(TaskItem task, bool isDark) {
    final textStyle = TextStyle(
      fontSize: 11,
      color: context.appColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('创建时间：${_formatTimestamp(task.createdAt)}', style: textStyle),
        const SizedBox(height: 4),
        Text('修改时间：${_formatTimestamp(task.updatedAt)}', style: textStyle),
      ],
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
              color: context.appColors.text,
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
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设置重复',
            style: TextStyle(
              color: context.appColors.text,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              _buildRecurrenceChip('每天',
                  () => _setRecurrence(taskId, RecurrenceFrequency.daily)),
              _buildRecurrenceChip('每周',
                  () => _setRecurrence(taskId, RecurrenceFrequency.weekly)),
              _buildRecurrenceChip('每月',
                  () => _setRecurrence(taskId, RecurrenceFrequency.monthly)),
              _buildRecurrenceChip('每年',
                  () => _setRecurrence(taskId, RecurrenceFrequency.yearly)),
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
    final startedAt =
        AppTime.fromMillisecondsSinceEpoch(session['startedAt'] as int);
    final dateStr = '${startedAt.month}/${startedAt.day}';
    final timeStr =
        '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    final mins = ((session['durationSeconds'] as int) / 60).floor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // 使用 Row + Flexible/Expanded 确保内容在窄屏下也能正确排列而不溢出
      child: Row(
        children: [
          Text(
            '$dateStr $timeStr',
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          // 使用 Expanded 包裹分钟数，确保其在中间占满空间
          Expanded(
            child: Text(
              '${mins}分钟',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            session['completed'] == true ? '✓' : '○',
            style: TextStyle(
              fontSize: 12,
              color: (session['completed'] == true)
                  ? context.appColors.success
                  : (context.appColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _selectDueDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate != null ? DateTime.parse(_dueDate!) : AppTime.now(),
      firstDate: AppTime.now().subtract(const Duration(days: 365)),
      lastDate: AppTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      final dateStr = AppTime.formatDate(date);
      setState(() {
        _dueDate = dateStr;
        _dueDateController.text = dateStr;
      });
      ref
          .read(taskProvider.notifier)
          .updateTask(widget.taskId, {'dueDate': _dueDate});
    }
  }

  void _selectDueTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _dueTime != null
          ? TimeOfDay(
              hour: int.parse(_dueTime!.split(':')[0]),
              minute: int.parse(_dueTime!.split(':')[1]))
          : TimeOfDay.fromDateTime(AppTime.now()),
    );
    if (time != null) {
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      setState(() {
        _dueTime = timeStr;
        _dueTimeController.text = timeStr;
      });
      ref
          .read(taskProvider.notifier)
          .updateTask(widget.taskId, {'dueTime': _dueTime});
    }
  }

  void _saveTitle(String taskId) {
    if (_titleController.text.trim().isNotEmpty) {
      ref
          .read(taskProvider.notifier)
          .updateTask(taskId, {'title': _titleController.text.trim()});
    }
  }

  void _saveNotes(String taskId) {
    ref
        .read(taskProvider.notifier)
        .updateTask(taskId, {'notes': _notesController.text.trim()});
  }

  void _saveExpectedMinutes(String taskId) {
    final mins = int.tryParse(_expectedMinutesController.text);
    ref
        .read(taskProvider.notifier)
        .updateTask(taskId, {'expectedMinutes': mins});
  }
}
