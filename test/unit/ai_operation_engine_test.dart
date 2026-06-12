import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation.dart';
import 'package:focus_my_time/features/ai_assistant/models/ai_operation_type.dart';
import 'package:focus_my_time/features/ai_assistant/services/ai_operation_engine.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

void main() {
  group('AiOperationEngine.validate', () {
    final lists = [
      TaskList(
        id: 'list-today',
        name: '20260612',
        isSystem: false,
        sortOrder: 0,
        createdAt: 1000,
        updatedAt: 1000,
      ),
    ];

    test('allows create_list when the list already exists', () {
      final operation = AiOperation(
        id: 'op-1',
        messageId: 'msg-1',
        type: AiOperationType.createList,
        params: {'name': '20260612'},
        summary: '创建清单 "20260612"',
        createdAt: 1000,
      );

      final error = AiOperationEngine.validate(
        operation,
        currentTasks: const [],
        currentLists: lists,
      );

      expect(error, isNull);
    });

    test('accepts an existing list name as create_task listId', () {
      final operation = AiOperation(
        id: 'op-2',
        messageId: 'msg-1',
        type: AiOperationType.createTask,
        params: {'title': '写周报', 'listId': '20260612'},
        summary: '创建任务 "写周报"',
        createdAt: 1000,
      );

      final error = AiOperationEngine.validate(
        operation,
        currentTasks: const [],
        currentLists: lists,
      );

      expect(error, isNull);
    });
  });
}
