import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_timer/features/tasks/providers/task_provider.dart';

void main() {
  group('TaskItem model (TaskItem class)', () {
    final testTask = TaskItem(
      id: 'task-1',
      listId: 'list-1',
      title: '测试任务',
      notes: 'Some notes',
      completed: false,
      dueDate: '2024-01-15',
      sortOrder: 0,
      isMyDay: true,
      createdAt: 1000,
      updatedAt: 1000,
    );

    test('TaskItem copyWith creates new instance with updated values', () {
      final updated = testTask.copyWith(title: '新标题', completed: true);
      expect(updated.title, '新标题');
      expect(updated.completed, true);
      expect(updated.id, 'task-1'); // unchanged
    });

    test('TaskItem copyWith preserves original when not specified', () {
      final updated = testTask.copyWith();
      expect(updated.title, testTask.title);
      expect(updated.notes, testTask.notes);
      expect(updated.dueDate, testTask.dueDate);
    });

    test('TaskItem supports my day flag', () {
      expect(testTask.isMyDay, true);
      final withoutMyDay = testTask.copyWith(isMyDay: false);
      expect(withoutMyDay.isMyDay, false);
    });

    test('TaskItem supports recurrence config', () {
      final config = {'frequency': 'daily', 'interval': 1};
      final recurringTask = TaskItem(
        id: 'task-2',
        listId: 'list-1',
        title: '重复任务',
        completed: false,
        sortOrder: 0,
        isMyDay: false,
        recurrenceConfig: config,
        createdAt: 1000,
        updatedAt: 1000,
      );
      expect(recurringTask.recurrenceConfig, config);
    });

    test('TaskItem can be completed', () {
      final completed = testTask.copyWith(completed: true);
      expect(completed.completed, true);
      expect(completed.completedAt, null); // completedAt is nullable
    });

    test('TaskItem dueDate can be set', () {
      expect(testTask.dueDate, '2024-01-15');
      final updated = testTask.copyWith(dueDate: '2024-02-01');
      expect(updated.dueDate, '2024-02-01');
    });
  });
}