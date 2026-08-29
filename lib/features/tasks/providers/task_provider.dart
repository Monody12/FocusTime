import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';
import 'package:focus_my_time/features/calendar/services/calendar_service.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/core/utils/recurrence_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TaskSortMode {
  manual,
  createdAscending,
  createdDescending,
  updatedAscending,
  updatedDescending,
  titleAscending,
  titleDescending,
  dueDateAscending,
  dueDateDescending,
}

class TaskViewPreferences {
  static const startupViewSettingKey = 'startupTaskListView';
  static const startupViewMyDay = 'myDay';
  static const startupViewLastViewed = 'lastViewed';
  static const lastViewedListKey = 'lastViewedTaskListId';
}

class TaskList {
  final String id;
  final String name;
  final bool isSystem;
  final int sortOrder;
  final String iconKey;
  final bool pinned;
  final int? topOrder;
  final bool hidden;
  final int createdAt;
  final int updatedAt;
  final bool archived;
  final int? archivedAt;

  TaskList({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.sortOrder,
    this.iconKey = 'list',
    this.pinned = false,
    this.topOrder,
    this.hidden = false,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.archivedAt,
  });

  TaskList copyWith({
    String? id,
    String? name,
    bool? isSystem,
    int? sortOrder,
    String? iconKey,
    bool? pinned,
    int? topOrder,
    bool? hidden,
    int? createdAt,
    int? updatedAt,
    bool? archived,
    int? archivedAt,
  }) => TaskList(
    id: id ?? this.id,
    name: name ?? this.name,
    isSystem: isSystem ?? this.isSystem,
    sortOrder: sortOrder ?? this.sortOrder,
    iconKey: iconKey ?? this.iconKey,
    pinned: pinned ?? this.pinned,
    topOrder: topOrder ?? this.topOrder,
    hidden: hidden ?? this.hidden,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archived: archived ?? this.archived,
    archivedAt: archivedAt ?? this.archivedAt,
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
  final String? calendarEventId;
  final int createdAt;
  final int updatedAt;
  final bool archived;
  final int? archivedAt;

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
    this.calendarEventId,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.archivedAt,
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
    String? calendarEventId,
    int? createdAt,
    int? updatedAt,
    bool? archived,
    int? archivedAt,
    bool clearNotes = false,
    bool clearDueDate = false,
    bool clearDueTime = false,
    bool clearReminder = false,
    bool clearCalendarEventId = false,
  }) => TaskItem(
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
    calendarEventId: clearCalendarEventId
        ? null
        : (calendarEventId ?? this.calendarEventId),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archived: archived ?? this.archived,
    archivedAt: archivedAt ?? this.archivedAt,
  );
}

List<TaskItem> sortTaskItems(Iterable<TaskItem> tasks, TaskSortMode sortMode) {
  final sorted = tasks.toList();
  sorted.sort((a, b) {
    var comparison = switch (sortMode) {
      TaskSortMode.manual => a.sortOrder.compareTo(b.sortOrder),
      TaskSortMode.createdAscending => a.createdAt.compareTo(b.createdAt),
      TaskSortMode.createdDescending => b.createdAt.compareTo(a.createdAt),
      TaskSortMode.updatedAscending => a.updatedAt.compareTo(b.updatedAt),
      TaskSortMode.updatedDescending => b.updatedAt.compareTo(a.updatedAt),
      TaskSortMode.titleAscending => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      TaskSortMode.titleDescending => b.title.toLowerCase().compareTo(
        a.title.toLowerCase(),
      ),
      TaskSortMode.dueDateAscending => _compareDueDates(a, b, ascending: true),
      TaskSortMode.dueDateDescending => _compareDueDates(
        a,
        b,
        ascending: false,
      ),
    };
    if (comparison != 0) return comparison;

    comparison = a.sortOrder.compareTo(b.sortOrder);
    if (comparison != 0) return comparison;
    comparison = a.createdAt.compareTo(b.createdAt);
    if (comparison != 0) return comparison;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

int _compareDueDates(TaskItem a, TaskItem b, {required bool ascending}) {
  final aDate = a.dueDate;
  final bDate = b.dueDate;
  if (aDate == null && bDate == null) return 0;
  if (aDate == null) return 1;
  if (bDate == null) return -1;

  var comparison = aDate.compareTo(bDate);
  if (!ascending) comparison = -comparison;
  if (comparison != 0) return comparison;

  final aTime = a.dueTime;
  final bTime = b.dueTime;
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  comparison = aTime.compareTo(bTime);
  return ascending ? comparison : -comparison;
}

TaskList? resolveLastViewedTaskList(
  Iterable<TaskList> lists,
  String? lastViewedListId,
) {
  return lists
      .where((list) => list.id == lastViewedListId && !list.archived)
      .firstOrNull;
}

class TaskState {
  final List<TaskList> lists;
  final List<TaskItem> tasks;
  final String currentListId;
  final String currentViewType; // 'my-day', 'all-tasks', 'custom'
  final String? selectedTaskId;
  final bool isLoading;
  final TaskSortMode sortMode;

  TaskState({
    this.lists = const [],
    this.tasks = const [],
    this.currentListId = 'system-my-day',
    this.currentViewType = 'my-day',
    this.selectedTaskId,
    this.isLoading = false,
    this.sortMode = TaskSortMode.manual,
  });

  TaskState copyWith({
    List<TaskList>? lists,
    List<TaskItem>? tasks,
    String? currentListId,
    String? currentViewType,
    String? selectedTaskId,
    bool? isLoading,
    TaskSortMode? sortMode,
    bool clearSelectedTask = false,
  }) => TaskState(
    lists: lists ?? this.lists,
    tasks: tasks ?? this.tasks,
    currentListId: currentListId ?? this.currentListId,
    currentViewType: currentViewType ?? this.currentViewType,
    selectedTaskId: clearSelectedTask
        ? null
        : (selectedTaskId ?? this.selectedTaskId),
    isLoading: isLoading ?? this.isLoading,
    sortMode: sortMode ?? this.sortMode,
  );
}

class TaskNotifier extends StateNotifier<TaskState> {
  final Map<String, TaskItem> _knownReminderTasks = {};
  final Set<String> _completionInProgress = {};
  late final Future<void> Function() _syncCompletedListener;

  TaskNotifier() : super(TaskState()) {
    _syncCompletedListener = _handleExternalSyncCompleted;
    SyncService.addSyncCompletedListener(_syncCompletedListener);
    _initialize();
  }

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      await loadLists();
      await _restoreStartupList();
      await loadTasks(showLoading: false);
    } catch (e, stackTrace) {
      dev.log('[TaskNotifier] 初始化任务清单失败', error: e, stackTrace: stackTrace);
      if (mounted) state = state.copyWith(isLoading: false);
    }

    try {
      // 使用完整数据集恢复提醒，不受当前视图过滤限制。
      await _refreshRemindersAndCalendarFromDatabase();
    } catch (e, stackTrace) {
      dev.log('[TaskNotifier] 初始化提醒失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _restoreStartupList() async {
    final startupView = await AppDatabase.getSetting(
      TaskViewPreferences.startupViewSettingKey,
    );
    if (startupView != TaskViewPreferences.startupViewLastViewed) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastViewedListId = prefs.getString(
      TaskViewPreferences.lastViewedListKey,
    );
    final lastViewedList = resolveLastViewedTaskList(
      state.lists,
      lastViewedListId,
    );
    if (lastViewedList == null) return;

    state = state.copyWith(
      currentListId: lastViewedList.id,
      currentViewType: _viewTypeForList(lastViewedList),
    );
  }

  @override
  void dispose() {
    SyncService.removeSyncCompletedListener(_syncCompletedListener);
    super.dispose();
  }

  static TaskList _listFromMap(Map<String, dynamic> m) {
    return TaskList(
      id: m['id'] as String,
      name: m['name'] as String,
      isSystem: m['isSystem'] == true,
      sortOrder: m['sortOrder'] as int,
      iconKey: m['iconKey'] as String? ?? 'list',
      pinned: m['pinned'] == true,
      topOrder: m['topOrder'] as int?,
      hidden: m['hidden'] == true,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
      archived: m['archived'] == true,
      archivedAt: m['archivedAt'] as int?,
    );
  }

  static TaskItem _taskFromMap(Map<String, dynamic> m) {
    return TaskItem(
      id: m['id'] as String,
      listId: m['listId'] as String,
      title: m['title'] as String,
      notes: m['notes'] as String?,
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
      calendarEventId: m['calendarEventId'] as String?,
      createdAt: m['createdAt'] as int,
      updatedAt: m['updatedAt'] as int,
      archived: m['archived'] == true,
      archivedAt: m['archivedAt'] as int?,
    );
  }

  static String _viewTypeForList(TaskList list) {
    switch (list.id) {
      case 'system-my-day':
        return 'my-day';
      case 'system-important':
        return 'important';
      case 'system-all-tasks':
        return 'all-tasks';
      default:
        return 'custom';
    }
  }

  Future<void> loadLists() async {
    final dbLists = await AppDatabase.getLists();
    if (!mounted) return;

    final lists = dbLists.map(_listFromMap).toList();
    state = state.copyWith(lists: lists);
  }

  Future<void> loadTasks({bool showLoading = true}) async {
    if (showLoading) state = state.copyWith(isLoading: true);
    final viewType = state.currentViewType;
    final listId = state.currentListId;
    try {
      List<Map<String, dynamic>> dbTasks;
      if (viewType == 'my-day') {
        dbTasks = await AppDatabase.getMyDayTasks();
      } else if (viewType == 'important') {
        dbTasks = await AppDatabase.getImportantTasks();
      } else if (viewType == 'all-tasks') {
        dbTasks = await AppDatabase.getAllTasks();
      } else {
        dbTasks = await AppDatabase.getTasksByList(listId);
      }
      if (!mounted) return;

      final tasks = dbTasks.map(_taskFromMap).toList();

      state = state.copyWith(tasks: tasks, isLoading: false);
    } catch (e) {
      if (!mounted) return;

      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setCurrentList(String listId, String viewType) async {
    state = state.copyWith(currentListId: listId, currentViewType: viewType);
    await loadTasks();
  }

  void setSortMode(TaskSortMode sortMode) {
    if (state.sortMode == sortMode) return;
    state = state.copyWith(sortMode: sortMode);
  }

  Future<void> persistLastViewedList(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      TaskViewPreferences.lastViewedListKey,
      listId,
    );
    if (!saved) {
      throw StateError('保存上次停留清单失败');
    }
  }

  void setSelectedTask(String? taskId) {
    if (state.selectedTaskId == taskId) return;

    state = state.copyWith(
      selectedTaskId: taskId,
      clearSelectedTask: taskId == null,
    );
  }

  List<TaskList> get listsSnapshot => state.lists;

  Future<TaskList> createList(String name) async {
    final result = await AppDatabase.createList(name);
    final list = _listFromMap(result);
    state = state.copyWith(lists: [...state.lists, list]);
    _triggerSync();
    return list;
  }

  Future<void> updateList(String id, String name) async {
    await AppDatabase.updateList(id, name);
    final lists = state.lists
        .map((l) => l.id == id ? l.copyWith(name: name) : l)
        .toList();
    state = state.copyWith(lists: lists);
    _triggerSync();
  }

  Future<void> updateListIcon(String id, String iconKey) async {
    await AppDatabase.updateListCustomization(id, iconKey: iconKey);
    state = state.copyWith(
      lists: state.lists
          .map((l) => l.id == id ? l.copyWith(iconKey: iconKey) : l)
          .toList(),
    );
    _triggerSync();
  }

  Future<void> pinList(String id) async {
    final visibleTopLists = state.lists
        .where((l) => l.pinned && !l.hidden)
        .toList();
    final topOrder = visibleTopLists.length;
    await AppDatabase.updateListCustomization(
      id,
      pinned: true,
      hidden: false,
      topOrder: topOrder,
    );
    await loadLists();
    _triggerSync();
  }

  Future<void> unpinList(String id) async {
    await AppDatabase.updateListCustomization(
      id,
      pinned: false,
      clearTopOrder: true,
    );
    await loadLists();
    _triggerSync();
  }

  Future<void> hideSystemList(String id) async {
    await AppDatabase.updateListCustomization(id, hidden: true);
    await loadLists();
    if (state.currentListId == id) {
      final fallback =
          state.lists.where((list) => list.pinned && !list.hidden).toList()
            ..sort(
              (a, b) => (a.topOrder ?? a.sortOrder).compareTo(
                b.topOrder ?? b.sortOrder,
              ),
            );
      if (fallback.isNotEmpty) {
        await setCurrentList(
          fallback.first.id,
          _viewTypeForList(fallback.first),
        );
      } else {
        await setCurrentList('system-all-tasks', 'all-tasks');
      }
    }
    _triggerSync();
  }

  Future<void> reorderTopLists(List<String> listIds) async {
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

    await AppDatabase.reorderTopLists(listIds);
    await loadLists();
    _triggerSync();
  }

  Future<void> resetListIcons() async {
    await AppDatabase.resetListIcons();
    await loadLists();
    _triggerSync();
  }

  Future<void> resetTopListOrder() async {
    await AppDatabase.resetTopListOrder();
    await loadLists();
    _triggerSync();
  }

  Future<void> deleteList(String id) async {
    await AppDatabase.deleteList(id);
    final lists = state.lists.where((l) => l.id != id).toList();
    state = state.copyWith(lists: lists);
    _triggerSync();
  }

  Future<void> archiveList(String id) async {
    final tasksToArchive = (await AppDatabase.getTasksByList(
      id,
    )).map(_taskFromMap).toList();
    final wasCurrentList = state.currentListId == id;
    await AppDatabase.archiveList(id);

    final lists = state.lists.where((l) => l.id != id).toList();
    final tasks = state.tasks.where((t) => t.listId != id).toList();
    state = state.copyWith(
      lists: lists,
      tasks: tasks,
      currentListId: wasCurrentList ? 'system-my-day' : state.currentListId,
      currentViewType: wasCurrentList ? 'my-day' : state.currentViewType,
      clearSelectedTask:
          state.selectedTaskId != null &&
          tasksToArchive.any((t) => t.id == state.selectedTaskId),
    );
    if (wasCurrentList) {
      await loadTasks(showLoading: false);
    }

    _triggerSync();
    await _cancelTaskIntegrations(tasksToArchive);
  }

  Future<void> archiveTask(String id) async {
    final dbTask = await AppDatabase.getTaskById(id);
    final task =
        state.tasks.where((t) => t.id == id).firstOrNull ??
        (dbTask == null ? null : _taskFromMap(dbTask));
    await AppDatabase.archiveTask(id);
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != id).toList(),
      clearSelectedTask: state.selectedTaskId == id,
    );

    _triggerSync();
    if (task != null) {
      await _cancelTaskIntegrations([task]);
    }
  }

  Future<void> restoreArchivedList(String id) async {
    await AppDatabase.restoreList(id);
    await loadLists();
    await loadTasks(showLoading: false);
    _triggerSync();
    await _refreshRemindersAndCalendarFromDatabase();
  }

  Future<void> restoreArchivedTask(String id) async {
    await AppDatabase.restoreTask(id);
    await loadLists();
    await loadTasks(showLoading: false);
    _triggerSync();
    await _refreshRemindersAndCalendarFromDatabase();
  }

  Future<void> deleteArchivedList(String id) async {
    await AppDatabase.deleteList(id);
    await loadLists();
    await loadTasks(showLoading: false);
    _triggerSync();
    await _refreshRemindersAndCalendarFromDatabase();
  }

  Future<void> deleteArchivedTask(String id) async {
    await AppDatabase.deleteTask(id);
    await loadTasks(showLoading: false);
    _triggerSync();
    await _refreshRemindersAndCalendarFromDatabase();
  }

  Future<({bool success, bool tokenExpired})> sync({
    bool background = false,
  }) async {
    if (!SyncService.isLoggedIn) {
      return (success: false, tokenExpired: false);
    }

    if (!background) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final result = await SyncService.fullSync(notifyListeners: false);
      if (result.success) {
        await loadLists();
        await loadTasks();
        // 同步完成后刷新所有提醒和日历（必须使用完整数据集，不受当前视图过滤影响）
        try {
          await _refreshRemindersAndCalendarFromDatabase();
        } catch (e, stackTrace) {
          dev.log(
            '[TaskNotifier] 同步完成后刷新提醒失败',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
      if (!background) state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      if (!background) state = state.copyWith(isLoading: false);
      return (success: false, tokenExpired: false);
    }
  }

  void _triggerSync() {
    SyncService.triggerBackgroundSync();
  }

  Future<void> _handleExternalSyncCompleted() async {
    if (!mounted) return;
    await loadLists();
    await loadTasks(showLoading: false);
    try {
      await _refreshRemindersAndCalendarFromDatabase();
    } catch (e, stackTrace) {
      dev.log('[TaskNotifier] 外部同步后刷新提醒失败', error: e, stackTrace: stackTrace);
    }
  }

  /// Reload every task-facing cache after a database restore. This also
  /// reconciles timers and calendar entries that belonged to removed tasks.
  Future<void> reloadAfterDataRestore() async {
    await loadLists();
    if (!mounted) return;

    final selectedListStillExists = state.lists.any(
      (list) => list.id == state.currentListId,
    );
    if (state.currentViewType == 'custom' && !selectedListStillExists) {
      state = state.copyWith(
        currentListId: 'system-my-day',
        currentViewType: 'my-day',
        clearSelectedTask: true,
      );
    } else {
      state = state.copyWith(clearSelectedTask: true);
    }

    await loadTasks(showLoading: false);
    await _refreshRemindersAndCalendarFromDatabase();
  }

  Future<void> _cancelTaskIntegrations(List<TaskItem> tasks) async {
    for (final task in tasks) {
      try {
        await ReminderService.cancelReminder(task.id);
      } catch (e) {
        // 取消通知失败不影响归档结果，恢复时会按数据库状态重新扫描。
      }
      if (task.calendarEventId != null) {
        try {
          await CalendarService.removeTask(task.calendarEventId!);
        } catch (e) {
          // Android 14+ 可能拒绝删除日历事件，降级方案已在 CalendarService 内部处理。
        }
      }
    }
  }

  Future<void> _refreshRemindersAndCalendarFromDatabase() async {
    final previousTasks = Map<String, TaskItem>.from(_knownReminderTasks);
    final allTasks = await _loadAllTaskItems();
    await _reconcileRemovedIntegrations(previousTasks, allTasks);
    await ReminderService.refreshAll(allTasks);
    final refreshedTasks = await _loadAllTaskItems();
    _replaceKnownReminderTasks(refreshedTasks);
  }

  Future<List<TaskItem>> _loadAllTaskItems() async {
    final allDbTasks = await AppDatabase.getAllTasks();
    return allDbTasks.map(_taskFromMap).toList();
  }

  Future<void> _reconcileRemovedIntegrations(
    Map<String, TaskItem> previousTasks,
    List<TaskItem> currentTasks,
  ) async {
    final currentById = {for (final task in currentTasks) task.id: task};
    for (final previousTask in previousTasks.values) {
      final currentTask = currentById[previousTask.id];
      final removed = currentTask == null;
      final reminderDisabled =
          currentTask != null &&
          (currentTask.reminderAt == null || currentTask.completed);
      if (!removed && !reminderDisabled) continue;

      try {
        await ReminderService.cancelReminder(previousTask.id);
      } catch (e, stackTrace) {
        dev.log(
          '[TaskNotifier] 清理已移除任务的通知失败',
          error: e,
          stackTrace: stackTrace,
        );
      }
      if (previousTask.calendarEventId != null) {
        try {
          await CalendarService.removeTask(previousTask.calendarEventId!);
        } catch (e, stackTrace) {
          dev.log(
            '[TaskNotifier] 清理已移除任务的日历事件失败',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }

  void _replaceKnownReminderTasks(List<TaskItem> tasks) {
    _knownReminderTasks
      ..clear()
      ..addEntries(
        tasks
            .where(
              (task) => task.reminderAt != null || task.calendarEventId != null,
            )
            .map((task) => MapEntry(task.id, task)),
      );
  }

  void _rememberTaskIntegration(TaskItem task) {
    if (task.reminderAt != null || task.calendarEventId != null) {
      _knownReminderTasks[task.id] = task;
    } else {
      _knownReminderTasks.remove(task.id);
    }
  }

  Future<TaskItem> createTask(
    String title, {
    String? listId,
    bool isMyDay = false,
    DateTime? reminderAt,
  }) async {
    final targetListId =
        listId ??
        (state.currentListId == 'system-my-day' ||
                state.currentListId == 'system-all-tasks'
            ? 'system-all-tasks'
            : state.currentListId);

    final result = await AppDatabase.createTask(
      listId: targetListId,
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
      calendarEventId: result['calendarEventId'] as String?,
      createdAt: result['createdAt'] as int,
      updatedAt: result['updatedAt'] as int,
    );

    state = state.copyWith(tasks: [...state.tasks, task]);

    // 如果创建时带了提醒（虽然目前 UI 尚未直接支持），进行调度
    if (task.reminderAt != null) {
      final eventId = await ReminderService.scheduleUnifiedReminders(task);
      // 将日历事件 ID 持久化到本机数据库；该字段不跨设备同步
      if (eventId != null && eventId != task.calendarEventId) {
        await AppDatabase.updateTaskCalendarEventId(task.id, eventId);
      }
      _rememberTaskIntegration(
        task.copyWith(
          calendarEventId: eventId,
          clearCalendarEventId: eventId == null,
        ),
      );
    }

    _triggerSync();
    return task;
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
          calendarEventId: dbTask['calendarEventId'] as String?,
          createdAt: dbTask['createdAt'] as int,
          updatedAt: dbTask['updatedAt'] as int,
        );
      }
    }

    if (updatedTask != null) {
      final eventId = await ReminderService.scheduleUnifiedReminders(
        updatedTask,
      );
      // 将 eventId 持久化到本机数据库，不推进同步时间戳
      if (eventId != null && eventId != updatedTask.calendarEventId) {
        await AppDatabase.updateTaskCalendarEventId(id, eventId);
      }
      state = state.copyWith(
        tasks: state.tasks
            .map(
              (t) => t.id == id
                  ? t.copyWith(
                      calendarEventId: eventId,
                      clearCalendarEventId: eventId == null,
                    )
                  : t,
            )
            .toList(),
      );
      _rememberTaskIntegration(
        updatedTask.copyWith(
          calendarEventId: eventId,
          clearCalendarEventId: eventId == null,
        ),
      );
    }

    _triggerSync();
  }

  Future<void> setReminder(String taskId, DateTime? reminderAt) async {
    final updates = {'reminderAt': reminderAt?.millisecondsSinceEpoch};
    await updateTask(taskId, updates);
  }

  Future<void> deleteTask(String id) async {
    // 先查找任务（用于后续日历清理），必须在 DB 操作前获取引用
    final task = state.tasks.where((t) => t.id == id).firstOrNull;

    // 1. 数据库软删除（必须最先执行）
    await AppDatabase.deleteTask(id);

    // 2. 乐观更新 UI：立即从 state.tasks 中移除该任务，确保 UI 即时响应。
    //    此操作必须在提醒/日历清理之前，避免那些操作抛异常导致 UI 不更新。
    final tasks = state.tasks.where((t) => t.id != id).toList();
    state = state.copyWith(
      tasks: tasks,
      clearSelectedTask: state.selectedTaskId == id,
    );

    // 3. 触发同步（不 await，后台执行）
    _triggerSync();

    // 4. 清理提醒和日历事件（可能失败，不能阻塞核心删除流程）
    try {
      await ReminderService.cancelReminder(id);
    } catch (e) {
      // 取消通知失败不影响删除结果，用户仍可在设置中手动管理通知
    }
    if (task?.calendarEventId != null) {
      try {
        await CalendarService.removeTask(task!.calendarEventId!);
      } catch (e) {
        // Android 14+ 可能拒绝删除日历事件，降级方案已在 CalendarService 内部处理
      }
    }
    _knownReminderTasks.remove(id);
  }

  Future<void> toggleTaskComplete(String id) async {
    if (_completionInProgress.contains(id)) return;

    final task = state.tasks.where((t) => t.id == id).firstOrNull;
    if (task == null) return;

    _completionInProgress.add(id);
    try {
      final willComplete = !task.completed;
      TaskItem? newRecurringTask;

      if (willComplete && task.recurrenceConfig != null) {
        final now = AppTime.now();
        final config = RecurrenceConfig.fromJson(task.recurrenceConfig!);
        if (config.endsAfterOccurrences != null &&
            config.endsAfterOccurrences! <= 1) {
          await AppDatabase.updateTask(id, {'recurrenceConfig': null});
          await AppDatabase.toggleTaskComplete(id);
          await loadTasks(showLoading: false);
          _triggerSync();
          return;
        }

        state = state.copyWith(
          tasks: state.tasks
              .map(
                (t) => t.id == id
                    ? t.copyWith(
                        completed: true,
                        completedAt: now.millisecondsSinceEpoch,
                      )
                    : t,
              )
              .toList(),
        );

        final currentDue = task.dueDate != null
            ? DateTime.parse(task.dueDate!)
            : AppTime.now();
        final nextDue = getNextDateOnOrAfter(currentDue, config, now);
        if (config.endsAt != null &&
            nextDue.isAfter(DateTime.parse(config.endsAt!))) {
          await AppDatabase.updateTask(id, {'recurrenceConfig': null});
          await AppDatabase.toggleTaskComplete(id);
          await loadTasks(showLoading: false);
          _triggerSync();
          return;
        }
        final newDueDateStr = AppTime.formatDate(nextDue);

        int? newReminderAt;
        if (task.reminderAt != null) {
          final currentReminder = AppTime.fromMillisecondsSinceEpoch(
            task.reminderAt!,
          );
          final newReminder = AppTime.create(
            nextDue.year,
            nextDue.month,
            nextDue.day,
            currentReminder.hour,
            currentReminder.minute,
            currentReminder.second,
          );
          newReminderAt = newReminder.millisecondsSinceEpoch;
        }

        final newDbTask = await AppDatabase.completeRecurringTaskAndCreateNext(
          id: id,
          newDueDate: newDueDateStr,
          newReminderAt: newReminderAt,
          nextRecurrenceConfig: _nextRecurrenceConfig(task.recurrenceConfig!),
        );
        if (newDbTask != null) {
          newRecurringTask = _taskFromMap(newDbTask);
        }
      } else {
        await AppDatabase.toggleTaskComplete(id);
      }

      await loadTasks(showLoading: false);

      if (newRecurringTask != null) {
        await _scheduleTaskIntegration(newRecurringTask);
        await _runAutoArchiveIfNeeded();
      }

      // 处理原任务的提醒取消/重新调度
      final updatedTask = state.tasks.where((t) => t.id == id).firstOrNull;
      if (updatedTask != null) {
        await _scheduleTaskIntegration(updatedTask);
      }

      _triggerSync();
    } finally {
      _completionInProgress.remove(id);
    }
  }

  Future<void> _scheduleTaskIntegration(TaskItem task) async {
    final eventId = await ReminderService.scheduleUnifiedReminders(task);
    if (eventId != task.calendarEventId) {
      await AppDatabase.updateTaskCalendarEventId(task.id, eventId);
    }
    state = state.copyWith(
      tasks: state.tasks
          .map(
            (t) => t.id == task.id
                ? t.copyWith(
                    calendarEventId: eventId,
                    clearCalendarEventId: eventId == null,
                  )
                : t,
          )
          .toList(),
    );
    _rememberTaskIntegration(
      task.copyWith(
        calendarEventId: eventId,
        clearCalendarEventId: eventId == null,
      ),
    );
  }

  Future<void> _runAutoArchiveIfNeeded() async {
    final enabled =
        (await AppDatabase.getSetting('autoArchiveCompletedTasks')) == 'true';
    if (!enabled) return;
    final keepRaw = await AppDatabase.getSetting('autoArchiveKeepCount');
    final keepCount = (int.tryParse(keepRaw ?? '') ?? 3).clamp(0, 9);
    final archived = await AppDatabase.autoArchiveCompletedTasks(
      keepCount: keepCount,
    );
    if (archived > 0) {
      await loadTasks(showLoading: false);
    }
  }

  Map<String, dynamic> _nextRecurrenceConfig(Map<String, dynamic> rawConfig) {
    final config = RecurrenceConfig.fromJson(rawConfig);
    final occurrences = config.endsAfterOccurrences;
    if (occurrences == null) return rawConfig;
    final nextOccurrences = occurrences - 1;
    return config
        .copyWith(endsAfterOccurrences: nextOccurrences.clamp(1, 99))
        .toJson();
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
    final previousTasks = state.tasks;
    final tasks = [...previousTasks];
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
    try {
      await AppDatabase.reorderTasks(taskIds);
      // 3. 静默加载最新状态（不触发 loading 状态）
      await loadTasks(showLoading: false);
      _triggerSync();
    } catch (_) {
      if (mounted) state = state.copyWith(tasks: previousTasks);
      rethrow;
    }
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
