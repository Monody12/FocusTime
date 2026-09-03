import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/features/tasks/presentation/widgets/task_item.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

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

  group('任务排序拖动手势', () {
    final task = TaskItem(
      id: 'drag-task',
      listId: 'list-1',
      title: '可排序任务',
      completed: false,
      sortOrder: 0,
      isMyDay: false,
      createdAt: 1,
      updatedAt: 1,
    );

    Future<void> pumpTask(WidgetTester tester, TargetPlatform platform) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme.copyWith(platform: platform),
              home: Scaffold(
                body: TaskItemWidget(
                  task: task,
                  index: 0,
                  isSelected: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('Android 使用独立排序手柄且不注册跨清单长按拖动', (tester) async {
      await pumpTask(tester, TargetPlatform.android);
      expect(find.byType(ReorderableDragStartListener), findsOneWidget);
      expect(find.byType(LongPressDraggable<String>), findsNothing);
      expect(find.byTooltip('拖动排序'), findsOneWidget);
    });

    testWidgets('桌面保留跨清单长按拖动和独立排序手柄', (tester) async {
      await pumpTask(tester, TargetPlatform.windows);
      expect(find.byType(ReorderableDragStartListener), findsOneWidget);
      expect(find.byType(LongPressDraggable<String>), findsOneWidget);
    });
  });
}
