import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';

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
  final bool isImportant;
  final int? reminderAt;
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
    this.isImportant = false,
    this.reminderAt,
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
    bool? isImportant,
    int? reminderAt,
    int? createdAt,
    int? updatedAt,
    bool clearNotes = false,
    bool clearDueDate = false,
    bool clearDueTime = false,
    bool clearReminder = false,
  }) =>
      TaskItem(
        id: id ?? this.id,
        listId: listId ?? this.listId,
        title: title ?? this.title,
        notes: clearNotes ? null : (notes ?? this.notes),
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
        sortOrder: sortOrder ?? this.sortOrder,
        isMyDay: isMyDay ?? this.isMyDay,
        myDayAddedAt: myDayAddedAt ?? this.myDayAddedAt,
        recurrenceConfig: recurrenceConfig ?? this.recurrenceConfig,
        expectedMinutes: expectedMinutes ?? this.expectedMinutes,
        isImportant: isImportant ?? this.isImportant,
        reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
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
    bool clearSelectedTask = false,
  }) =>
      TaskState(
        lists: lists ?? this.lists,
        tasks: tasks ?? this.tasks,
        currentListId: currentListId ?? this.currentListId,
        currentViewType: currentViewType ?? this.currentViewType,
        selectedTaskId: clearSelectedTask ? null : (selectedTaskId ?? this.selectedTaskId),
        isLoading: isLoading ?? this.isLoading,
      );
}

class TaskNotifier extends StateNotifier<TaskState> {
  TaskNotifier() : super(TaskState()) {
    loadLists();
    loadTasks().then((_) {
      // 首次加载完任务后，刷新所有提醒
      ReminderService.refreshAll(state.tasks);
    });
  }

  Future<void> loadLists() async {
    final dbLists = await AppDatabase.getLists();
    final lists = dbLists.map((m) => TaskList(
      id: m['id'] as String,
      name: m['name'] as String,
      // 使用 == true 进行健壮性判断，防止数据库返回 Null 或 0/1 时触发类型错误
      isSystem: m['isSystem'] == true,
      sortOrder: m['sortOrder'] as int,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
    )).toList();
    state = state.copyWith(lists: lists);
  }

  Future<void> loadTasks({bool showLoading = true}) async {
    if (showLoading) state = state.copyWith(isLoading: true);
    try {
      List<Map<String, dynamic>> dbTasks;
      if (state.currentViewType == 'my-day') {
        dbTasks = await AppDatabase.getMyDayTasks();
      } else if (state.currentViewType == 'important') {
        dbTasks = await AppDatabase.getImportantTasks();
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
        // 将数据库返回的动态值安全地转换为布尔值
        completed: m['completed'] == true,
        completedAt: m['completedAt'] as int?,
        dueDate: m['dueDate'] as String?,
        dueTime: m['dueTime'] as String?,
        sortOrder: m['sortOrder'] as int,
        isMyDay: m['isMyDay'] == true,
        myDayAddedAt: m['myDayAddedAt'] as int?,
        recurrenceConfig: m['recurrenceConfig'] as Map<String, dynamic>?,
        expectedMinutes: m['expectedMinutes'] as int?,
        isImportant: m['isImportant'] == true,
        reminderAt: m['reminderAt'] as int?,
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
    state = state.copyWith(selectedTaskId: taskId, clearSelectedTask: taskId == null);
  }

  Future<TaskList> createList(String name) async {
    final result = await AppDatabase.createList(name);
    final list = TaskList(
      id: result['id'] as String,
      name: result['name'] as String,
      isSystem: result['isSystem'] == true,
      sortOrder: result['sortOrder'] as int,
      createdAt: result['createdAt'] as int,
      updatedAt: result['updatedAt'] as int,
    );
    state = state.copyWith(lists: [...state.lists, list]);
    _triggerSync();
    return list;
  }

  Future<void> updateList(String id, String name) async {
    await AppDatabase.updateList(id, name);
    final lists = state.lists.map((l) => l.id == id ? l.copyWith(name: name) : l).toList();
    state = state.copyWith(lists: lists);
    _triggerSync();
  }

  Future<void> deleteList(String id) async {
    await AppDatabase.deleteList(id);
    final lists = state.lists.where((l) => l.id != id).toList();
    state = state.copyWith(lists: lists);
    _triggerSync();
  }

  Future<({bool success, bool tokenExpired})> sync({bool background = false}) async {
    if (!SyncService.isLoggedIn) {
      return (success: false, tokenExpired: false);
    }

    if (!background) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final result = await SyncService.fullSync();
      if (result.success) {
        await loadLists();
        await loadTasks();
        // 同步完成后刷新所有提醒
        ReminderService.refreshAll(state.tasks);
      }
      if (!background) state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      if (!background) state = state.copyWith(isLoading: false);
      return (success: false, tokenExpired: false);
    }
  }

  void _triggerSync() {
    sync(background: true);
  }

  Future<void> createTask(String title, {bool isMyDay = false, DateTime? reminderAt}) async {
    final listId = state.currentListId == 'system-my-day' || state.currentListId == 'system-all-tasks'
        ? 'system-all-tasks'
        : state.currentListId;
    
    final result = await AppDatabase.createTask(
      listId: listId, 
      title: title, 
      isMyDay: isMyDay,
      reminderAt: reminderAt?.millisecondsSinceEpoch,
    );
    
    final task = TaskItem(
      id: result['id'] as String,
      listId: result['listId'] as String,
      title: result['title'] as String,
      notes: result['notes'] as String?,
      completed: result['completed'] == true,
      completedAt: result['completedAt'] as int?,
      dueDate: result['dueDate'] as String?,
      dueTime: result['dueTime'] as String?,
      sortOrder: result['sortOrder'] as int,
      isMyDay: result['isMyDay'] == true,
      myDayAddedAt: result['myDayAddedAt'] as int?,
      recurrenceConfig: result['recurrenceConfig'] as Map<String, dynamic>?,
      expectedMinutes: result['expectedMinutes'] as int?,
      isImportant: result['isImportant'] == true,
      reminderAt: result['reminderAt'] as int?,
      createdAt: result['createdAt'] as int,
      updatedAt: result['updatedAt'] as int,
    );
    
    state = state.copyWith(tasks: [...state.tasks, task]);
    
    // 如果创建时带了提醒（虽然目前 UI 尚未直接支持），进行调度
    if (task.reminderAt != null) {
      ReminderService.scheduleReminder(task);
    }
    
    _triggerSync();
  }

  Future<void> updateTask(String id, Map<String, dynamic> updates) async {
    await AppDatabase.updateTask(id, updates);
    await loadTasks(showLoading: false);
    
    // 检查并调度提醒。即使任务不在当前视图列表中（state.tasks），也需要从数据库重新获取并调度。
    TaskItem? updatedTask = state.tasks.where((t) => t.id == id).firstOrNull;
    if (updatedTask == null) {
      final dbTask = await AppDatabase.getTaskById(id);
      if (dbTask != null) {
        updatedTask = TaskItem(
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

    if (updatedTask != null) {
      if (updatedTask.completed) {
        ReminderService.cancelReminder(id);
      } else {
        ReminderService.scheduleReminder(updatedTask);
      }
    }
    
    _triggerSync();
  }

  Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    final updates = {'reminderAt': reminderAt?.millisecondsSinceEpoch};
    await updateTask(taskId, updates);
  }

  Future<void> deleteTask(String id) async {
    await AppDatabase.deleteTask(id);
    await ReminderService.cancelReminder(id);
    final tasks = state.tasks.where((t) => t.id != id).toList();
    state = state.copyWith(tasks: tasks, clearSelectedTask: state.selectedTaskId == id);
    _triggerSync();
  }

  Future<void> toggleTaskComplete(String id) async {
    await AppDatabase.toggleTaskComplete(id);
    await loadTasks(showLoading: false);
    
    // 处理提醒取消/重新调度
    final updatedTask = state.tasks.where((t) => t.id == id).firstOrNull;
    if (updatedTask != null) {
      if (updatedTask.completed) {
        ReminderService.cancelReminder(id);
      } else if (updatedTask.reminderAt != null) {
        ReminderService.scheduleReminder(updatedTask);
      }
    }
    
    _triggerSync();
  }

  Future<void> addToMyDay(String taskId) async {
    await AppDatabase.addToMyDay(taskId);
    await loadTasks(showLoading: false);
    _triggerSync();
  }

  Future<void> removeFromMyDay(String taskId) async {
    await AppDatabase.removeFromMyDay(taskId);
    await loadTasks(showLoading: false);
    _triggerSync();
  }

  Future<void> toggleTaskImportant(String taskId) async {
    final task = state.tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    await AppDatabase.updateTask(taskId, {'isImportant': !task.isImportant});
    await loadTasks(showLoading: false);
    _triggerSync();
  }

  Future<void> moveTaskToList(String taskId, String listId) async {
    await AppDatabase.updateTask(taskId, {'listId': listId});
    await loadTasks(showLoading: false);
    _triggerSync();
  }

  Future<void> reorderTasks(List<String> taskIds) async {
    // 1. 乐观更新：立即在内存中更新任务顺序，避免 UI 抖动
    final tasks = [...state.tasks];
    final idToIndex = {for (int i = 0; i < taskIds.length; i++) taskIds[i]: i};
    
    // 只重新对传入的任务进行排序，保持其他任务（如已完成）的相对位置
    tasks.sort((a, b) {
      final indexA = idToIndex[a.id];
      final indexB = idToIndex[b.id];
      if (indexA != null && indexB != null) return indexA.compareTo(indexB);
      if (indexA != null) return -1; // 排序中的任务靠前
      if (indexB != null) return 1;
      return a.sortOrder.compareTo(b.sortOrder); // 保持原有顺序
    });

    state = state.copyWith(tasks: tasks);

    // 2. 异步更新数据库
    await AppDatabase.reorderTasks(taskIds);
    // 3. 静默加载最新状态（不触发 loading 状态）
    await loadTasks(showLoading: false);
    _triggerSync();
  }

  Future<void> reorderLists(List<String> listIds, {int offset = 0}) async {
    // 1. 乐观更新
    final lists = [...state.lists];
    final idToIndex = {for (int i = 0; i < listIds.length; i++) listIds[i]: i};
    
    lists.sort((a, b) {
      final indexA = idToIndex[a.id];
      final indexB = idToIndex[b.id];
      if (indexA != null && indexB != null) return indexA.compareTo(indexB);
      if (indexA != null) return -1;
      if (indexB != null) return 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    state = state.copyWith(lists: lists);

    // 2. 异步更新数据库
    await AppDatabase.reorderLists(listIds, offset: offset);
    // 3. 静默加载最新状态
    await loadLists();
    _triggerSync();
  }
}

final taskProvider = StateNotifierProvider<TaskNotifier, TaskState>((ref) {
  return TaskNotifier();
});
