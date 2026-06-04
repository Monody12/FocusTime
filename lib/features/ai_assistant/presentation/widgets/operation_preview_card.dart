import 'package:flutter/material.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';

class OperationPreviewCard extends StatelessWidget {
  final AiOperation operation;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onReject;

  const OperationPreviewCard({
    super.key,
    required this.operation,
    required this.onApprove,
    required this.onEdit,
    required this.onReject,
  });

  bool get _hasTimeInfo {
    final p = operation.params;
    return p.containsKey('dueDate') || p.containsKey('reminderAt');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDelete = operation.type.name == 'deleteTask';
    final isCompleted = operation.status == AiOperationStatus.approved ||
        operation.status == AiOperationStatus.rejected ||
        operation.status == AiOperationStatus.failed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDelete
              ? Colors.red.withOpacity(0.5)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: isDelete ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _typeIcon(),
                  size: 20,
                  color: isDelete
                      ? Colors.red
                      : (isDark ? AppColors.darkAccent : AppColors.lightAccent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    operation.summary,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ),
                if (isCompleted) _statusChip(isDark),
              ],
            ),
            if (_hasTimeInfo) ...[
              const SizedBox(height: 6),
              _buildTimeDetail(isDark),
            ],
            if (operation.reasoning != null &&
                operation.reasoning!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                operation.reasoning!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
            if (operation.errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                '错误: ${operation.errorMessage}',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
            if (!isCompleted) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton('拒绝', Icons.close, Colors.grey, onReject),
                  const SizedBox(width: 8),
                  _actionButton(
                      '编辑',
                      Icons.edit_outlined,
                      isDark ? AppColors.darkAccent : AppColors.lightAccent,
                      onEdit),
                  const SizedBox(width: 8),
                  _actionButton(
                      '批准', Icons.check, const Color(0xFF10B981), onApprove),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeDetail(bool isDark) {
    final params = operation.params;
    final dueDate = params['dueDate'] as String?;
    final dueTime = params['dueTime'] as String?;
    final reminderAt = params['reminderAt'] as String?;
    final expectedMinutes = params['expectedMinutes'] as int?;

    DateTime? startDt;
    if (reminderAt != null) {
      startDt = AppTime.parseSelectedIso(reminderAt);
    }
    DateTime? endDt;
    if (dueDate != null && dueTime != null) {
      try {
        final parts = dueTime.split(':');
        final dateParts = dueDate.split('-');
        endDt = AppTime.create(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      } catch (_) {}
    } else if (dueDate != null) {
      try {
        final dateParts = dueDate.split('-');
        endDt = AppTime.create(int.parse(dateParts[0]), int.parse(dateParts[1]),
            int.parse(dateParts[2]));
      } catch (_) {}
    }

    final duration = expectedMinutes ??
        (startDt != null && endDt != null
            ? endDt.difference(startDt).inMinutes
            : null);

    final chips = <Widget>[];

    if (startDt != null) {
      chips.add(_timeChip(
        Icons.notifications_outlined,
        '提醒 ${_fmtTime(startDt)}',
        isDark,
        accent: Colors.orange,
      ));
      if (endDt != null) {
        chips.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.arrow_forward,
              size: 12,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary),
        ));
      }
    }
    if (endDt != null) {
      chips.add(_timeChip(
        Icons.flag_outlined,
        startDt != null
            ? '截止 ${_fmtTime(endDt)}'
            : '截止 ${_fmtDate(endDt)} ${_fmtTime(endDt)}',
        isDark,
      ));
    }
    if (duration != null && duration > 0) {
      chips.add(_timeChip(Icons.timer_outlined, '$duration分钟', isDark));
    }
    if (dueDate != null && startDt == null && endDt == null) {
      chips.add(_timeChip(Icons.calendar_today, dueDate, isDark));
    } else if (dueDate != null) {
      chips.add(_timeChip(Icons.calendar_today, dueDate, isDark));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  Widget _timeChip(IconData icon, String label, bool isDark, {Color? accent}) {
    final color = accent ??
        (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    return AppTime.formatTime(dt);
  }

  String _fmtDate(DateTime dt) {
    return AppTime.formatDate(dt);
  }

  Widget _statusChip(bool isDark) {
    final label = operation.statusLabel;
    Color color;
    switch (operation.status) {
      case AiOperationStatus.approved:
        color = const Color(0xFF10B981);
        break;
      case AiOperationStatus.rejected:
        color = Colors.grey;
        break;
      case AiOperationStatus.failed:
        color = Colors.red;
        break;
      default:
        color = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon() {
    switch (operation.type.name) {
      case 'createTask':
        return Icons.add_circle_outline;
      case 'updateTask':
        return Icons.edit_outlined;
      case 'deleteTask':
        return Icons.delete_outline;
      case 'setDueDate':
        return Icons.calendar_today;
      case 'setReminder':
        return Icons.notifications_outlined;
      case 'setRecurrence':
        return Icons.repeat;
      case 'addToMyDay':
        return Icons.wb_sunny_outlined;
      case 'toggleImportant':
        return Icons.star_outline;
      case 'moveToList':
        return Icons.move_to_inbox;
      case 'reorderTasks':
        return Icons.reorder;
      case 'createList':
        return Icons.playlist_add;
      case 'updateList':
        return Icons.edit_note;
      case 'deleteList':
        return Icons.playlist_remove;
      default:
        return Icons.help_outline;
    }
  }
}
