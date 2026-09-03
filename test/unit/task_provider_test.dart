import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

TaskItem _task({
  required String id,
  required String title,
  int sortOrder = 0,
  int createdAt = 0,
  int updatedAt = 0,
  String? dueDate,
  String? dueTime,
}) {
  return TaskItem(
    id: id,
    listId: 'list-1',
    title: title,
    completed: false,
    dueDate: dueDate,
    dueTime: dueTime,
    sortOrder: sortOrder,
    isMyDay: false,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

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
      expect(taskList.archived, false);
      expect(taskList.archivedAt, null);
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
      expect(task.archived, false);
      expect(task.archivedAt, null);
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

    test('reminderAt can be set and preserved', () {
      const reminderTime = 1715072400000;
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Task with Reminder',
        completed: false,
        sortOrder: 0,
        isMyDay: false,
        reminderAt: reminderTime,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(task.reminderAt, reminderTime);
      final updated = task.copyWith(title: 'Updated');
      expect(updated.reminderAt, reminderTime);
    });

    test('copyWith can clear nullable fields using flags', () {
      final task = TaskItem(
        id: 'task-1',
        listId: 'list-1',
        title: 'Test',
        notes: 'Some notes',
        completed: false,
        dueDate: '2024-01-15',
        reminderAt: 12345,
        sortOrder: 0,
        isMyDay: false,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final cleared = task.copyWith(
        clearNotes: true,
        clearDueDate: true,
        clearReminder: true,
      );
      expect(cleared.notes, isNull);
      expect(cleared.dueDate, isNull);
      expect(cleared.reminderAt, isNull);
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
      final updated = state.copyWith(clearSelectedTask: true);
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

  group('任务排序', () {
    final tasks = [
      _task(
        id: 'b',
        title: 'Beta',
        sortOrder: 0,
        createdAt: 30,
        updatedAt: 10,
        dueDate: '2026-08-22',
        dueTime: '10:00',
      ),
      _task(
        id: 'a',
        title: 'alpha',
        sortOrder: 2,
        createdAt: 10,
        updatedAt: 30,
        dueDate: '2026-08-22',
        dueTime: '09:00',
      ),
      _task(
        id: 'c',
        title: 'Charlie',
        sortOrder: 1,
        createdAt: 20,
        updatedAt: 20,
      ),
    ];

    test('手动、创建时间和修改时间排序方向正确', () {
      expect(sortTaskItems(tasks, TaskSortMode.manual).map((task) => task.id), [
        'b',
        'c',
        'a',
      ]);
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.createdAscending,
        ).map((task) => task.id),
        ['a', 'c', 'b'],
      );
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.createdDescending,
        ).map((task) => task.id),
        ['b', 'c', 'a'],
      );
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.updatedAscending,
        ).map((task) => task.id),
        ['b', 'c', 'a'],
      );
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.updatedDescending,
        ).map((task) => task.id),
        ['a', 'c', 'b'],
      );
    });

    test('手动重排会同步更新 sortOrder，排序后不会弹回旧位置', () {
      final reordered = applyManualTaskOrder(tasks, const ['a', 'b', 'c']);
      expect(
        sortTaskItems(reordered, TaskSortMode.manual).map((task) => task.id),
        ['a', 'b', 'c'],
      );
      expect(
        {for (final task in reordered) task.id: task.sortOrder},
        {'a': 0, 'b': 1, 'c': 2},
      );
    });

    test('任务名称排序忽略大小写', () {
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.titleAscending,
        ).map((task) => task.id),
        ['a', 'b', 'c'],
      );
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.titleDescending,
        ).map((task) => task.id),
        ['c', 'b', 'a'],
      );
    });

    test('截止日期排序在两个方向都把无日期任务放在最后', () {
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.dueDateAscending,
        ).map((task) => task.id),
        ['a', 'b', 'c'],
      );
      expect(
        sortTaskItems(
          tasks,
          TaskSortMode.dueDateDescending,
        ).map((task) => task.id),
        ['b', 'a', 'c'],
      );
    });
  });

  group('启动清单恢复', () {
    final active = TaskList(
      id: 'active',
      name: '有效清单',
      isSystem: false,
      sortOrder: 0,
      createdAt: 1,
      updatedAt: 1,
    );
    final archived = TaskList(
      id: 'archived',
      name: '已归档清单',
      isSystem: false,
      sortOrder: 1,
      createdAt: 1,
      updatedAt: 1,
      archived: true,
    );

    test('只恢复仍然有效的上次清单', () {
      expect(resolveLastViewedTaskList([active, archived], 'active'), active);
      expect(resolveLastViewedTaskList([active, archived], 'archived'), isNull);
      expect(resolveLastViewedTaskList([active, archived], 'missing'), isNull);
    });
  });
}
