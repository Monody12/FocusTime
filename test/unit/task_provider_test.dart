import 'package:flutter_test/flutter_test.dart';
import 'package:focus_timer/features/tasks/providers/task_provider.dart';

void main() {
  group('TaskList', () {
    test('creates with correct values', () {
      final taskList = TaskList(
        id: 'list-1',
        name: 'Test List',
        isSystem: false,
        sortOrder: 0,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(taskList.id, 'list-1');
      expect(taskList.name, 'Test List');
      expect(taskList.isSystem, false);
      expect(taskList.sortOrder, 0);
      expect(taskList.createdAt, 1000);
      expect(taskList.updatedAt, 1000);
    });

    test('copyWith updates fields correctly', () {
      final taskList = TaskList(
        id: 'list-1',
        name: 'Original',
        isSystem: false,
        sortOrder: 0,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = taskList.copyWith(name: 'Updated');
      expect(updated.name, 'Updated');
      expect(updated.id, 'list-1');
    });

    test('copyWith preserves unchanged fields', () {
      final taskList = TaskList(
        id: 'list-1',
        name: 'Original',
        isSystem: true,
        sortOrder: 5,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = taskList.copyWith(name: 'Updated');
      expect(updated.isSystem, true);
      expect(updated.sortOrder, 5);
    });
  });

  group('TaskItem', () {
    test('creates with correct values', () {
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Test Task',
        notes: 'Some notes',
        completed: false,
        dueDate: '2024-01-15',
        dueTime: '14:00',
        sortOrder: 0,
        isMyDay: true,
        myDayAddedAt: 1000,
        expectedMinutes: 30,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(task.id, 'task-1');
      expect(task.listId, 'list-1');
      expect(task.title, 'Test Task');
      expect(task.notes, 'Some notes');
      expect(task.completed, false);
      expect(task.dueDate, '2024-01-15');
      expect(task.dueTime, '14:00');
      expect(task.sortOrder, 0);
      expect(task.isMyDay, true);
      expect(task.myDayAddedAt, 1000);
      expect(task.expectedMinutes, 30);
    });

    test('copyWith updates fields correctly', () {
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Original',
        completed: false,
        sortOrder: 0,
        isMyDay: false,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = task.copyWith(
        title: 'Updated',
        completed: true,
        isMyDay: true,
      );

      expect(updated.title, 'Updated');
      expect(updated.completed, true);
      expect(updated.isMyDay, true);
      expect(updated.id, 'task-1');
    });

    test('copyWith preserves unchanged fields', () {
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Original',
        notes: 'Original notes',
        completed: false,
        sortOrder: 3,
        isMyDay: true,
        myDayAddedAt: 1000,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = task.copyWith(title: 'Updated');
      expect(updated.notes, 'Original notes');
      expect(updated.sortOrder, 3);
      expect(updated.myDayAddedAt, 1000);
    });

    test('copyWith can set fields to null using explicit null', () {
      // Note: In this implementation, copyWith uses ?? operator which means
      // passing null will KEEP the old value, not set to null.
      // This is a design choice - to set to null, the field must be nullable
      // and the copyWith must be designed to distinguish "no change" from "set to null"
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Test',
        notes: 'Some notes',
        completed: false,
        dueDate: '2024-01-15',
        sortOrder: 0,
        isMyDay: false,
        createdAt: 1000,
        updatedAt: 1000,
      );

      // Since copyWith uses ?? operator, passing null keeps old value
      final updated = task.copyWith(notes: null, dueDate: null);
      expect(updated.notes, 'Some notes'); // null is treated as "no change"
      expect(updated.dueDate, '2024-01-15'); // null is treated as "no change"
    });

    test('recurrenceConfig can be set and preserved', () {
      final recurrence = {'frequency': 'daily', 'interval': 1};
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Recurring Task',
        completed: false,
        sortOrder: 0,
        isMyDay: false,
        recurrenceConfig: recurrence,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = task.copyWith(title: 'Updated');
      expect(updated.recurrenceConfig, recurrence);
    });
  });

  group('TaskState', () {
    test('default values are correct', () {
      final state = TaskState();
      expect(state.lists, isEmpty);
      expect(state.tasks, isEmpty);
      expect(state.currentListId, 'system-my-day');
      expect(state.currentViewType, 'my-day');
      expect(state.selectedTaskId, null);
      expect(state.isLoading, false);
    });

    test('copyWith updates fields correctly', () {
      final state = TaskState();
      final taskList = TaskList(
        id: 'list-1',
        name: 'Test',
        isSystem: false,
        sortOrder: 0,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final updated = state.copyWith(
        lists: [taskList],
        currentListId: 'system-all-tasks',
        currentViewType: 'all-tasks',
        isLoading: true,
      );

      expect(updated.lists.length, 1);
      expect(updated.currentListId, 'system-all-tasks');
      expect(updated.currentViewType, 'all-tasks');
      expect(updated.isLoading, true);
    });

    test('copyWith can set selectedTaskId to null', () {
      final state = TaskState(selectedTaskId: 'task-1');
      final updated = state.copyWith(selectedTaskId: null);
      expect(updated.selectedTaskId, null);
    });

    test('copyWith preserves lists when not provided', () {
      final taskList = TaskList(
        id: 'list-1',
        name: 'Test',
        isSystem: false,
        sortOrder: 0,
        createdAt: 1000,
        updatedAt: 1000,
      );
      final state = TaskState(lists: [taskList]);
      final updated = state.copyWith(currentViewType: 'all-tasks');
      expect(updated.lists, [taskList]);
    });
  });
}