import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/app_database.dart';

class TaskList {
  final String id;
  final String name;
  final bool isSystem;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  TaskList({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  TaskList copyWith({
    String? id,
    String? name,
    bool? isSystem,
    int? sortOrder,
    int? createdAt,
    int? updatedAt,
  }) =>
      TaskList(
        id: id ?? this.id,
        name: name ?? this.name,
        isSystem: isSystem ?? this.isSystem,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class TaskItem {
  final String id;
  final String listId;
  final String title;
  final String? notes;
  final bool completed;
  final int? completedAt;
  final String? dueDate;
  final String? dueTime;
  final int sortOrder;
  final bool isMyDay;
  final int? myDayAddedAt;
  final Map<String, dynamic>? recurrenceConfig;
  final int? expectedMinutes;
  final int createdAt;
  final int updatedAt;

  TaskItem({
    required this.id,
    required this.listId,
    required this.title,
    this.notes,
    required this.completed,
    this.completedAt,
    this.dueDate,
    this.dueTime,
    required this.sortOrder,
    required this.isMyDay,
    this.myDayAddedAt,
    this.recurrenceConfig,
    this.expectedMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  TaskItem copyWith({
    String? id,
    String? listId,
    String? title,
    String? notes,
    bool? completed,
    int? completedAt,
    String? dueDate,
    String? dueTime,
    int? sortOrder,
    bool? isMyDay,
    int? myDayAddedAt,
    Map<String, dynamic>? recurrenceConfig,
    int? expectedMinutes,
    int? createdAt,
    int? updatedAt,
  }) =>
      TaskItem(
        id: id ?? this.id,
        listId: listId ?? this.listId,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        dueDate: dueDate ?? this.dueDate,
        dueTime: dueTime ?? this.dueTime,
        sortOrder: sortOrder ?? this.sortOrder,
        isMyDay: isMyDay ?? this.isMyDay,
        myDayAddedAt: myDayAddedAt ?? this.myDayAddedAt,
        recurrenceConfig: recurrenceConfig ?? this.recurrenceConfig,
        expectedMinutes: expectedMinutes ?? this.expectedMinutes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class TaskState {
  final List<TaskList> lists;
  final List<TaskItem> tasks;
  final String currentListId;
  final String currentViewType; // 'my-day', 'all-tasks', 'custom'
  final String? selectedTaskId;
  final bool isLoading;

  TaskState({
    this.lists = const [],
    this.tasks = const [],
    this.currentListId = 'system-my-day',
    this.currentViewType = 'my-day',
    this.selectedTaskId,
    this.isLoading = false,
  });

  TaskState copyWith({
    List<TaskList>? lists,
    List<TaskItem>? tasks,
    String? currentListId,
    String? currentViewType,
    String? selectedTaskId,
    bool? isLoading,
  }) =>
      TaskState(
        lists: lists ?? this.lists,
        tasks: tasks ?? this.tasks,
        currentListId: currentListId ?? this.currentListId,
        currentViewType: currentViewType ?? this.currentViewType,
        selectedTaskId: selectedTaskId,
        isLoading: isLoading ?? this.isLoading,
      );
}

class TaskNotifier extends StateNotifier<TaskState> {
  TaskNotifier() : super(TaskState()) {
    loadLists();
    loadTasks();
  }

  Future<void> loadLists() async {
    final dbLists = await AppDatabase.getLists();
    final lists = dbLists.map((m) => TaskList(
      id: m['id'] as String,
      name: m['name'] as String,
      isSystem: m['isSystem'] as bool,
      sortOrder: m['sortOrder'] as int,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
    )).toList();
    state = state.copyWith(lists: lists);
  }

  Future<void> loadTasks() async {
    state = state.copyWith(isLoading: true);
    try {
      List<Map<String, dynamic>> dbTasks;
      if (state.currentViewType == 'my-day') {
        dbTasks = await AppDatabase.getMyDayTasks();
      } else if (state.currentViewType == 'all-tasks') {
        dbTasks = await AppDatabase.getAllTasks();
      } else {
        dbTasks = await AppDatabase.getTasksByList(state.currentListId);
      }

      final tasks = dbTasks.map((m) => TaskItem(
        id: m['id'] as String,
        listId: m['listId'] as String,
        title: m['title'] as String,
        notes: m['notes'] as String?,
        completed: m['completed'] as bool,
        completedAt: m['completedAt'] as int?,
        dueDate: m['dueDate'] as String?,
        dueTime: m['dueTime'] as String?,
        sortOrder: m['sortOrder'] as int,
        isMyDay: m['isMyDay'] as bool,
        myDayAddedAt: m['myDayAddedAt'] as int?,
        recurrenceConfig: m['recurrenceConfig'] as Map<String, dynamic>?,
        expectedMinutes: m['expectedMinutes'] as int?,
        createdAt: m['createdAt'] as int,
        updatedAt: m['updatedAt'] as int,
      )).toList();

      state = state.copyWith(tasks: tasks, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setCurrentList(String listId, String viewType) async {
    state = state.copyWith(currentListId: listId, currentViewType: viewType);
    await loadTasks();
  }

  void setSelectedTask(String? taskId) {
    state = state.copyWith(selectedTaskId: taskId);
  }

  Future<TaskList> createList(String name) async {
    final result = await AppDatabase.createList(name);
    final list = TaskList(
      id: result['id'] as String,
      name: result['name'] as String,
      isSystem: result['isSystem'] as bool,
      sortOrder: result['sortOrder'] as int,
      createdAt: result['createdAt'] as int,
      updatedAt: result['updatedAt'] as int,
    );
    state = state.copyWith(lists: [...state.lists, list]);
    return list;
  }

  Future<void> updateList(String id, String name) async {
    await AppDatabase.updateList(id, name);
    final lists = state.lists.map((l) => l.id == id ? l.copyWith(name: name) : l).toList();
    state = state.copyWith(lists: lists);
  }

  Future<void> deleteList(String id) async {
    await AppDatabase.deleteList(id);
    final lists = state.lists.where((l) => l.id != id).toList();
    state = state.copyWith(lists: lists);
  }

  Future<void> createTask(String title, {bool isMyDay = false}) async {
    final listId = state.currentListId == 'system-my-day' || state.currentListId == 'system-all-tasks'
        ? 'system-all-tasks'
        : state.currentListId;
    final result = await AppDatabase.createTask(listId: listId, title: title, isMyDay: isMyDay);
    final task = TaskItem(
      id: result['id'] as String,
      listId: result['listId'] as String,
      title: result['title'] as String,
      notes: result['notes'] as String?,
      completed: result['completed'] as bool,
      completedAt: result['completedAt'] as int?,
      dueDate: result['dueDate'] as String?,
      dueTime: result['dueTime'] as String?,
      sortOrder: result['sortOrder'] as int,
      isMyDay: result['isMyDay'] as bool,
      myDayAddedAt: result['myDayAddedAt'] as int?,
      recurrenceConfig: result['recurrenceConfig'] as Map<String, dynamic>?,
      expectedMinutes: result['expectedMinutes'] as int?,
      createdAt: result['createdAt'] as int,
      updatedAt: result['updatedAt'] as int,
    );
    state = state.copyWith(tasks: [...state.tasks, task]);
  }

  Future<void> updateTask(String id, Map<String, dynamic> updates) async {
    await AppDatabase.updateTask(id, updates);
    await loadTasks();
  }

  Future<void> deleteTask(String id) async {
    await AppDatabase.deleteTask(id);
    final tasks = state.tasks.where((t) => t.id != id).toList();
    state = state.copyWith(tasks: tasks, selectedTaskId: null);
  }

  Future<void> toggleTaskComplete(String id) async {
    await AppDatabase.toggleTaskComplete(id);
    await loadTasks();
  }

  Future<void> addToMyDay(String taskId) async {
    await AppDatabase.addToMyDay(taskId);
    await loadTasks();
  }

  Future<void> removeFromMyDay(String taskId) async {
    await AppDatabase.removeFromMyDay(taskId);
    await loadTasks();
  }

  Future<void> reorderTasks(List<String> taskIds) async {
    await AppDatabase.reorderTasks(taskIds);
    await loadTasks();
  }
}

final taskProvider = StateNotifierProvider<TaskNotifier, TaskState>((ref) {
  return TaskNotifier();
});