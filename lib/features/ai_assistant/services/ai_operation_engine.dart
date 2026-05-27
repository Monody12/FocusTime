import 'dart:convert';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation_type.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

class AiOperationEngine {
  static String? validate(
    AiOperation operation, {
    required List<TaskItem> currentTasks,
    required List<TaskList> currentLists,
  }) {
    final params = operation.params;
    final now = DateTime.now();

    switch (operation.type) {
      case AiOperationType.createTask:
        final dueTime = params['dueTime'] as String?;
        final dueDate = params['dueDate'] as String?;
        if (dueDate != null && dueTime != null) {
          final dt = _parseDateTime(dueDate, dueTime);
          if (dt != null && dt.isBefore(now)) {
            return '任务时间 ($dueDate $dueTime) 不能早于当前时间';
          }
        }
        final title = params['title'] as String?;
        if (title == null || title.trim().isEmpty) {
          return '任务标题不能为空';
        }
        // If creating in a dated list, ensure it exists
        if (params.containsKey('listId')) {
          final listId = params['listId'] as String;
          if (!currentLists.any((l) => l.id == listId)) {
            return null; // Will be auto-created by _ensureList
          }
        }
        return null;

      case AiOperationType.updateTask:
      case AiOperationType.deleteTask:
      case AiOperationType.setDueDate:
      case AiOperationType.setReminder:
      case AiOperationType.setRecurrence:
      case AiOperationType.addToMyDay:
      case AiOperationType.toggleImportant:
      case AiOperationType.moveToList:
        final taskId = params['taskId'] as String?;
        if (taskId == null) return '缺少任务 ID';
        if (!currentTasks.any((t) => t.id == taskId)) {
          return '任务 $taskId 不存在';
        }
        return null;

      case AiOperationType.reorderTasks:
        final taskIds = params['taskIds'] as List?;
        if (taskIds == null || taskIds.isEmpty) return '任务 ID 列表不能为空';
        for (final id in taskIds) {
          if (!currentTasks.any((t) => t.id == id)) {
            return '任务 $id 不存在';
          }
        }
        return null;

      case AiOperationType.createList:
        final listName = params['name'] as String?;
        if (listName == null || listName.trim().isEmpty) {
          return '清单名称不能为空';
        }
        if (currentLists.any((l) => l.name == listName)) {
          return '清单 "$listName" 已存在';
        }
        return null;

      case AiOperationType.updateList:
        final listId = params['listId'] as String?;
        if (listId == null) return '缺少清单 ID';
        if (!currentLists.any((l) => l.id == listId)) {
          return '清单不存在';
        }
        return null;

      case AiOperationType.deleteList:
        final listId = params['listId'] as String?;
        if (listId == null) return '缺少清单 ID';
        final list = currentLists.where((l) => l.id == listId).firstOrNull;
        if (list == null) return '清单不存在';
        if (list.isSystem) return '不能删除系统清单';
        return null;
    }
  }

  static Future<AiOperation> execute({
    required AiOperation operation,
    required TaskNotifier taskNotifier,
  }) async {
    try {
      await _dispatch(operation, taskNotifier);
      return operation.copyWith(status: AiOperationStatus.approved);
    } catch (e) {
      return operation.copyWith(
        status: AiOperationStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<List<AiOperation>> executeAll({
    required List<AiOperation> operations,
    required TaskNotifier taskNotifier,
  }) async {
    final results = <AiOperation>[];
    for (final op in operations) {
      if (op.status == AiOperationStatus.rejected) {
        results.add(op);
        continue;
      }
      final result = await execute(
        operation: op,
        taskNotifier: taskNotifier,
      );
      results.add(result);
    }
    return results;
  }

  static Future<void> _dispatch(
    AiOperation op,
    TaskNotifier taskNotifier,
  ) async {
    final params = op.params;

    switch (op.type) {
      case AiOperationType.createTask:
        // Ensure target list exists (for dated lists etc.), resolve to real ID
        if (params.containsKey('listId')) {
          final realId = await _ensureList(params['listId'] as String, taskNotifier);
          params['listId'] = realId;
        }
        await _executeCreateTask(params, taskNotifier);
        break;

      case AiOperationType.updateTask:
        final taskId = params['taskId'] as String;
        final updates = <String, dynamic>{};
        if (params.containsKey('title')) updates['title'] = params['title'];
        if (params.containsKey('notes')) updates['notes'] = params['notes'];
        if (params.containsKey('dueDate')) updates['dueDate'] = params['dueDate'];
        if (params.containsKey('dueTime')) updates['dueTime'] = params['dueTime'];
        if (params.containsKey('expectedMinutes')) updates['expectedMinutes'] = params['expectedMinutes'];
        if (params.containsKey('isImportant')) updates['isImportant'] = params['isImportant'];
        if (updates.isNotEmpty) {
          await taskNotifier.updateTask(taskId, updates);
        }
        break;

      case AiOperationType.deleteTask:
        await taskNotifier.deleteTask(params['taskId'] as String);
        break;

      case AiOperationType.setDueDate:
        await taskNotifier.updateTask(params['taskId'] as String, {
          if (params.containsKey('dueDate')) 'dueDate': params['dueDate'],
          if (params.containsKey('dueTime')) 'dueTime': params['dueTime'],
        });
        break;

      case AiOperationType.setReminder:
        final taskId = params['taskId'] as String;
        final reminderStr = params['reminderAt'] as String?;
        DateTime? reminderAt;
        if (reminderStr != null) {
          reminderAt = DateTime.tryParse(reminderStr);
        }
        await taskNotifier.setReminder(taskId, reminderAt);
        break;

      case AiOperationType.setRecurrence:
        final taskId = params['taskId'] as String;
        final frequency = params['frequency'] as String?;
        final interval = params['interval'] as int?;
        if (frequency != null) {
          final config = <String, dynamic>{
            'frequency': frequency,
            'interval': interval ?? 1,
          };
          await taskNotifier.updateTask(taskId, {'recurrenceConfig': config});
        }
        break;

      case AiOperationType.addToMyDay:
        await taskNotifier.addToMyDay(params['taskId'] as String);
        break;

      case AiOperationType.toggleImportant:
        await taskNotifier.toggleTaskImportant(params['taskId'] as String);
        break;

      case AiOperationType.moveToList:
        if (params.containsKey('listId')) {
          await _ensureList(params['listId'] as String, taskNotifier);
        }
        await taskNotifier.moveTaskToList(
          params['taskId'] as String,
          params['listId'] as String,
        );
        break;

      case AiOperationType.reorderTasks:
        final taskIds = (params['taskIds'] as List).cast<String>();
        await taskNotifier.reorderTasks(taskIds);
        break;

      case AiOperationType.createList:
        await taskNotifier.createList(params['name'] as String);
        break;

      case AiOperationType.updateList:
        await taskNotifier.updateList(
          params['listId'] as String,
          params['name'] as String,
        );
        break;

      case AiOperationType.deleteList:
        await taskNotifier.deleteList(params['listId'] as String);
        break;
    }
  }

  /// Resolve a list reference (by ID or by name) and create if missing.
  /// Returns the actual DB list ID.
  static Future<String> _ensureList(
    String listRef,
    TaskNotifier taskNotifier,
  ) async {
    // ignore: invalid_use_of_protected_member
    final currentLists = taskNotifier.state.lists;

    // First try exact ID match
    var match = currentLists.where((l) => l.id == listRef).firstOrNull;
    if (match != null) return match.id;

    // Then try name match
    match = currentLists.where((l) => l.name == listRef).firstOrNull;
    if (match != null) return match.id;

    // Create new list with the reference as name
    final created = await taskNotifier.createList(listRef);
    return created.id;
  }

  static Future<void> _executeCreateTask(
    Map<String, dynamic> params,
    TaskNotifier taskNotifier,
  ) async {
    final title = params['title'] as String;

    final task = await taskNotifier.createTask(
      title,
      isMyDay: params['isMyDay'] == true,
      reminderAt: params['reminderAt'] != null
          ? DateTime.tryParse(params['reminderAt'] as String)
          : null,
    );

    final updates = <String, dynamic>{};
    if (params.containsKey('notes')) updates['notes'] = params['notes'];
    if (params.containsKey('dueDate')) updates['dueDate'] = params['dueDate'];
    if (params.containsKey('dueTime')) updates['dueTime'] = params['dueTime'];
    if (params.containsKey('expectedMinutes')) updates['expectedMinutes'] = params['expectedMinutes'];
    if (params.containsKey('isImportant')) updates['isImportant'] = params['isImportant'] == true;
    if (params.containsKey('listId')) updates['listId'] = params['listId'];

    if (updates.isNotEmpty) {
      await taskNotifier.updateTask(task.id, updates);
    }
  }

  static DateTime? _parseDateTime(String date, String time) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final dateParts = date.split('-');
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        hour,
        minute,
      );
    } catch (_) {
      return null;
    }
  }

  /// Count tasks in a list (for delete confirmation)
  static Future<int> countTasksInList(String listId) async {
    final tasks = await AppDatabase.getTasksByList(listId);
    return tasks.where((t) => t['completed'] != true).length;
  }

  /// Build AI operations from parsed DeepSeek tool calls
  static List<AiOperation> fromToolCalls(
    List<Map<String, dynamic>> toolCalls,
    String messageId,
  ) {
    final ops = <AiOperation>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < toolCalls.length; i++) {
      final tc = toolCalls[i];
      final func = tc['function'] as Map<String, dynamic>?;
      if (func == null) continue;

      final name = func['name'] as String?;
      final args = tc['_parsedArguments'] as Map<String, dynamic>? ??
          (func['arguments'] is String
              ? _safeJsonDecode(func['arguments'] as String)
              : func['arguments'] as Map<String, dynamic>?) ??
          <String, dynamic>{};

      final type = _typeFromName(name);
      if (type == null) continue;

      final summary = _buildSummary(type, args);
      final id = 'aio-${now + i}';

      ops.add(AiOperation(
        id: id,
        messageId: messageId,
        type: type,
        params: args,
        summary: summary,
        createdAt: now + i,
      ));
    }

    return ops;
  }

  static AiOperationType? _typeFromName(String? name) {
    switch (name) {
      case 'create_task':
        return AiOperationType.createTask;
      case 'update_task':
        return AiOperationType.updateTask;
      case 'delete_task':
        return AiOperationType.deleteTask;
      case 'set_recurrence':
        return AiOperationType.setRecurrence;
      case 'add_to_my_day':
        return AiOperationType.addToMyDay;
      case 'create_list':
        return AiOperationType.createList;
      case 'update_list':
        return AiOperationType.updateList;
      case 'delete_list':
        return AiOperationType.deleteList;
      default:
        return null;
    }
  }

  static String _buildSummary(AiOperationType type, Map<String, dynamic> args) {
    final title = args['title'] as String? ?? '';
    final taskId = args['taskId'] as String? ?? '';
    final listId = args['listId'] as String? ?? '';
    final listName = args['name'] as String? ?? '';
    final dueDate = args['dueDate'] as String?;
    final dueTime = args['dueTime'] as String?;
    final frequency = args['frequency'] as String?;

    switch (type) {
      case AiOperationType.createTask:
        final buf = StringBuffer('创建任务 "$title"');
        if (dueDate != null) {
          buf.write(' ($dueDate');
          if (dueTime != null) buf.write(' $dueTime');
          buf.write(')');
        }
        if (args['reminderAt'] != null) buf.write(' [提醒]');
        return buf.toString();
      case AiOperationType.updateTask:
        final changes = <String>[];
        if (args.containsKey('title')) changes.add('标题');
        if (args.containsKey('dueDate')) changes.add('截止日期');
        if (args.containsKey('dueTime')) changes.add('截止时间');
        if (args.containsKey('reminderAt')) changes.add('提醒');
        if (args.containsKey('expectedMinutes')) changes.add('时长');
        if (args.containsKey('notes')) changes.add('备注');
        if (args.containsKey('isImportant')) changes.add('重要性');
        final taskTitle = args['title'] as String?;
        if (taskTitle != null && taskTitle.isNotEmpty) {
          if (changes.isNotEmpty) {
            return '修改任务 "$taskTitle" - ${changes.join(', ')}';
          }
          return '修改任务 "$taskTitle"';
        }
        if (changes.isNotEmpty) {
          return '修改任务 (ID: $taskId) - ${changes.join(', ')}';
        }
        return '修改任务 (ID: $taskId)';
      case AiOperationType.deleteTask:
        return '删除任务 "$title" (ID: $taskId)';
      case AiOperationType.setRecurrence:
        return '设置重复: "$title" ($frequency)';
      case AiOperationType.addToMyDay:
        return '加入我的一天: "$title"';
      case AiOperationType.createList:
        return '创建清单 "$listName"';
      case AiOperationType.updateList:
        return '重命名清单为 "$listName" (ID: $listId)';
      case AiOperationType.deleteList:
        return '删除清单 "$listName" (ID: $listId)';
      default:
        return '操作: ${type.name}';
    }
  }

  static Map<String, dynamic>? _safeJsonDecode(String s) {
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
