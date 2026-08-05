import 'package:flutter/material.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';
import 'package:focus_my_time/data/database/app_database.dart';

class CalendarTaskDetailPage extends StatefulWidget {
  const CalendarTaskDetailPage({
    super.key,
    required this.taskId,
    required this.onClose,
  });

  final String taskId;
  final VoidCallback onClose;

  @override
  State<CalendarTaskDetailPage> createState() => _CalendarTaskDetailPageState();
}

class _CalendarTaskDetailPageState extends State<CalendarTaskDetailPage> {
  Map<String, dynamic>? _task;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CalendarTaskDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      setState(() {
        _task = null;
        _sessions = [];
        _loading = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final taskId = widget.taskId;
    try {
      final task = await AppDatabase.getTaskById(taskId, includeArchived: true);
      final sessions = task == null
          ? <Map<String, dynamic>>[]
          : await AppDatabase.getSessionsByTaskId(taskId);
      if (!mounted || widget.taskId != taskId) return;
      setState(() {
        _task = task;
        _sessions = sessions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || widget.taskId != taskId) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('任务详情加载失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 800;
    return SafeArea(
      top: isMobile,
      bottom: isMobile,
      child: Container(
        width: isMobile ? double.infinity : 340,
        color: context.appColors.surface,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Text(
            '任务详情',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '只读',
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.textSecondary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(AppIcons.close, size: AppIconSizes.nav),
            tooltip: '关闭',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final task = _task;
    if (task == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '任务不存在或已删除',
            style: TextStyle(color: context.appColors.textSecondary),
          ),
        ),
      );
    }

    final completed = task['completed'] == true;
    final archived = task['archived'] == true;
    final notes = (task['notes'] as String?)?.trim();
    final expectedMinutes = task['expectedMinutes'] as int?;
    final dueDate = task['dueDate'] as String?;
    final dueTime = task['dueTime'] as String?;
    final recurrence = task['recurrenceConfig'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompletionMark(completed),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task['title'] as String,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: completed
                        ? context.appColors.textSecondary
                        : context.appColors.text,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStatusLabel(
                completed ? AppIcons.taskComplete : AppIcons.taskIncomplete,
                completed ? '已完成' : '未完成',
                completed
                    ? context.appColors.success
                    : context.appColors.textSecondary,
              ),
              if (archived)
                _buildStatusLabel(
                  AppIcons.archive,
                  '已归档',
                  context.appColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('基本信息'),
          _buildInfoRow(
            AppIcons.list,
            '所属清单',
            task['listName'] as String? ?? '未知清单',
          ),
          _buildInfoRow(
            AppIcons.add,
            '创建时间',
            _formatTimestamp(task['createdAt'] as int),
          ),
          if (task['completedAt'] is int)
            _buildInfoRow(
              AppIcons.taskComplete,
              '完成时间',
              _formatTimestamp(task['completedAt'] as int),
            ),
          if (dueDate != null)
            _buildInfoRow(
              AppIcons.calendar,
              '截止时间',
              dueTime == null ? dueDate : '$dueDate $dueTime',
            ),
          if (expectedMinutes != null)
            _buildInfoRow(AppIcons.timer, '预期专注', '$expectedMinutes 分钟'),
          if (recurrence is Map<String, dynamic>)
            _buildInfoRow(
              AppIcons.repeat,
              '重复',
              _recurrenceSummary(recurrence),
            ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildSectionTitle('备注'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.background,
                border: Border.all(color: context.appColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                notes,
                style: TextStyle(height: 1.5, color: context.appColors.text),
              ),
            ),
          ],
          if (_sessions.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildSectionTitle('专注记录'),
            ..._sessions.take(5).map(_buildSessionRow),
            const SizedBox(height: 4),
            Text(
              '累计 ${_sessions.fold<int>(0, (sum, session) => sum + (session['durationSeconds'] as int)) ~/ 60} 分钟 · ${_sessions.length} 次',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionMark(bool completed) {
    return Semantics(
      label: completed ? '已完成' : '未完成',
      checked: completed,
      child: ExcludeSemantics(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: completed ? context.appColors.success : Colors.transparent,
            border: Border.all(
              color: completed
                  ? context.appColors.success
                  : context.appColors.border,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: completed
              ? const Icon(AppIcons.taskDone, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _buildStatusLabel(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: AppIconSizes.status, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.appColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            icon,
            size: AppIconSizes.compact,
            color: context.appColors.textSecondary,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.appColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: context.appColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session) {
    final minutes = (session['durationSeconds'] as int) ~/ 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AppIcon(
            AppIcons.focus,
            size: AppIconSizes.status,
            color: context.appColors.accentSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatTimestamp(session['startedAt'] as int),
              style: TextStyle(fontSize: 12, color: context.appColors.text),
            ),
          ),
          Text(
            '$minutes 分钟',
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    return AppTime.formatDateTimeFromMilliseconds(
      timestamp,
    ).replaceAll('-', '/');
  }

  String _recurrenceSummary(Map<String, dynamic> raw) {
    try {
      return getRecurrenceSummary(RecurrenceConfig.fromJson(raw));
    } catch (_) {
      return '重复任务';
    }
  }
}
