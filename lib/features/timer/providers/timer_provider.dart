import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/time_utils.dart';
import 'package:focus_timer/core/services/timer_notification_service.dart';
import 'package:focus_timer/data/database/app_database.dart';
import 'package:focus_timer/data/sync/sync_service.dart';
import 'package:focus_timer/features/tasks/providers/task_provider.dart';

enum TimerMode { singleCore, pomodoro }
enum TimerStatus { idle, running, paused, completed }

class SingleCoreConfig {
  final int minDuration;
  const SingleCoreConfig({this.minDuration = 25});
  SingleCoreConfig copyWith({int? minDuration}) =>
      SingleCoreConfig(minDuration: minDuration ?? this.minDuration);
}

class PomodoroConfig {
  final int focusDuration;
  final int breakDuration;
  final int longBreakDuration;
  final int cyclesBeforeLongBreak;
  final bool enableCycle;
  final int maxCycles;
  final bool autoStartNext;
  final bool autoStartBreak;

  const PomodoroConfig({
    this.focusDuration = 25,
    this.breakDuration = 5,
    this.longBreakDuration = 15,
    this.cyclesBeforeLongBreak = 4,
    this.enableCycle = false,
    this.maxCycles = 0,
    this.autoStartNext = false,
    this.autoStartBreak = false,
  });

  PomodoroConfig copyWith({
    int? focusDuration,
    int? breakDuration,
    int? longBreakDuration,
    int? cyclesBeforeLongBreak,
    bool? enableCycle,
    int? maxCycles,
    bool? autoStartNext,
    bool? autoStartBreak,
  }) =>
      PomodoroConfig(
        focusDuration: focusDuration ?? this.focusDuration,
        breakDuration: breakDuration ?? this.breakDuration,
        longBreakDuration: longBreakDuration ?? this.longBreakDuration,
        cyclesBeforeLongBreak: cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak,
        enableCycle: enableCycle ?? this.enableCycle,
        maxCycles: maxCycles ?? this.maxCycles,
        autoStartNext: autoStartNext ?? this.autoStartNext,
        autoStartBreak: autoStartBreak ?? this.autoStartBreak,
      );
}

class TimerState {
  final TimerMode timerMode;
  final TimerStatus timerStatus;
  final String currentTask;
  final String? currentTaskId;
  final List<String> taskHistory;
  final int totalSeconds;
  final int elapsedSeconds;
  final DateTime? targetTime;
  final int startedAt;
  final int plannedDurationSeconds;
  final SingleCoreConfig singleCoreConfig;
  final PomodoroConfig pomodoroConfig;
  final String timerPhase; // 'focus', 'break', 'long-break'
  final int currentCycle;
  final bool soundEnabled;
  final String notificationDuration; // 'short', 'long', 'persistent'
  final String notificationTemplate;

  TimerState({
    this.timerMode = TimerMode.singleCore,
    this.timerStatus = TimerStatus.idle,
    this.currentTask = '',
    this.currentTaskId,
    this.taskHistory = const [],
    this.totalSeconds = 0,
    this.elapsedSeconds = 0,
    this.targetTime,
    this.startedAt = 0,
    this.plannedDurationSeconds = 0,
    this.singleCoreConfig = const SingleCoreConfig(minDuration: 25),
    this.pomodoroConfig = const PomodoroConfig(),
    this.timerPhase = 'focus',
    this.currentCycle = 0,
    this.soundEnabled = true,
    this.notificationDuration = 'long',
    this.notificationTemplate = '计时完成！{task}',
  });

  TimerState copyWith({
    TimerMode? timerMode,
    TimerStatus? timerStatus,
    String? currentTask,
    String? currentTaskId,
    List<String>? taskHistory,
    int? totalSeconds,
    int? elapsedSeconds,
    DateTime? targetTime,
    int? startedAt,
    int? plannedDurationSeconds,
    SingleCoreConfig? singleCoreConfig,
    PomodoroConfig? pomodoroConfig,
    String? timerPhase,
    int? currentCycle,
    bool? soundEnabled,
    String? notificationDuration,
    String? notificationTemplate,
  }) =>
      TimerState(
        timerMode: timerMode ?? this.timerMode,
        timerStatus: timerStatus ?? this.timerStatus,
        currentTask: currentTask ?? this.currentTask,
        currentTaskId: currentTaskId ?? this.currentTaskId,
        taskHistory: taskHistory ?? this.taskHistory,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        targetTime: targetTime ?? this.targetTime,
        startedAt: startedAt ?? this.startedAt,
        plannedDurationSeconds: plannedDurationSeconds ?? this.plannedDurationSeconds,
        singleCoreConfig: singleCoreConfig ?? this.singleCoreConfig,
        pomodoroConfig: pomodoroConfig ?? this.pomodoroConfig,
        timerPhase: timerPhase ?? this.timerPhase,
        currentCycle: currentCycle ?? this.currentCycle,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        notificationDuration: notificationDuration ?? this.notificationDuration,
        notificationTemplate: notificationTemplate ?? this.notificationTemplate,
      );

  int get remainingSeconds => (totalSeconds - elapsedSeconds).clamp(0, totalSeconds);
  double get progress =>
      totalSeconds > 0 ? elapsedSeconds / totalSeconds : 0.0;
  String get formattedTime => formatTime(remainingSeconds.clamp(0, totalSeconds));
}

class TimerNotifier extends StateNotifier<TimerState> {
  Timer? _timer;
  final Ref _ref;

  TimerNotifier(this._ref) : super(TimerState()) {
    _loadState();
    _initNotificationListener();
  }

  /// 初始化通知中心按钮动作监听
  void _initNotificationListener() {
    TimerNotificationService.setActionListener((action) {
      dev.log('[TimerNotifier] 接收到通知动作: $action');
      switch (action) {
        case 'action:start_break':
          startBreak();
          break;
        case 'action:start_focus':
          startFocus();
          break;
        case 'action:skip_break':
          skipBreak();
          break;
        case 'action:stop_alarm':
          TimerNotificationService.stopAlarm();
          break;
      }
    });
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final timerModeStr = prefs.getString('timerMode') ?? 'singleCore';
    final timerStatusStr = prefs.getString('timerStatus') ?? 'idle';
    final timerPhase = prefs.getString('timerPhase') ?? 'focus';
    final currentCycle = prefs.getInt('currentCycle') ?? 0;
    final singleCoreMinDuration =
        prefs.getInt('singleCoreMinDuration') ?? 25;
    final focusDuration = prefs.getInt('focusDuration') ?? 25;
    final breakDuration = prefs.getInt('breakDuration') ?? 5;
    final longBreakDuration = prefs.getInt('longBreakDuration') ?? 15;
    final cyclesBeforeLongBreak = prefs.getInt('cyclesBeforeLongBreak') ?? 4;
    final enableCycle = prefs.getBool('enableCycle') ?? false;
    final autoStartNext = prefs.getBool('autoStartNext') ?? false;
    final autoStartBreak = prefs.getBool('autoStartBreak') ?? false;
    final soundEnabled = prefs.getBool('soundEnabled') ?? true;
    final notificationDuration = prefs.getString('notificationDuration') ?? 'long';
    final notificationTemplate = prefs.getString('notificationTemplate') ?? '计时完成！{task}';
    final taskHistoryStr = prefs.getString('taskHistory') ?? '';
    final taskHistory = taskHistoryStr.isEmpty
        ? <String>[]
        : taskHistoryStr.split(',').take(20).toList();

    // Timer running state
    final currentTask = prefs.getString('currentTask') ?? '';
    final currentTaskId = prefs.getString('currentTaskId');
    final totalSeconds = prefs.getInt('totalSeconds') ?? 0;
    final savedElapsedSeconds = prefs.getInt('elapsedSeconds') ?? 0;
    final startedAt = prefs.getInt('startedAt') ?? 0;
    final plannedDurationSeconds = prefs.getInt('plannedDurationSeconds') ?? 0;
    final targetTimeStr = prefs.getString('targetTime');

    DateTime? targetTime;
    if (targetTimeStr != null) {
      targetTime = DateTime.tryParse(targetTimeStr);
    }

    // If timer was running, calculate actual elapsed time
    int elapsedSeconds = savedElapsedSeconds;
    int actualElapsedSeconds = savedElapsedSeconds;
    if (timerStatusStr == 'running' && startedAt > 0) {
      final actualElapsed = (DateTime.now().millisecondsSinceEpoch - startedAt) ~/ 1000;
      elapsedSeconds = savedElapsedSeconds + actualElapsed;
      actualElapsedSeconds = actualElapsed;
    }

    state = state.copyWith(
      timerMode: timerModeStr == 'pomodoro' ? TimerMode.pomodoro : TimerMode.singleCore,
      timerStatus: timerStatusStr == 'running'
          ? TimerStatus.running
          : timerStatusStr == 'paused'
              ? TimerStatus.paused
              : TimerStatus.idle, // Reset completed to idle on app restart as requested
      timerPhase: timerPhase,
      currentCycle: currentCycle,
      currentTask: currentTask,
      currentTaskId: currentTaskId,
      totalSeconds: totalSeconds,
      elapsedSeconds: elapsedSeconds,
      startedAt: startedAt,
      plannedDurationSeconds: plannedDurationSeconds,
      targetTime: targetTime,
      singleCoreConfig: SingleCoreConfig(minDuration: singleCoreMinDuration),
      pomodoroConfig: PomodoroConfig(
        focusDuration: focusDuration,
        breakDuration: breakDuration,
        longBreakDuration: longBreakDuration,
        cyclesBeforeLongBreak: cyclesBeforeLongBreak,
        enableCycle: enableCycle,
        autoStartNext: autoStartNext,
        autoStartBreak: autoStartBreak,
      ),
      soundEnabled: soundEnabled,
      notificationDuration: notificationDuration,
      notificationTemplate: notificationTemplate,
      taskHistory: taskHistory,
    );

    // If timer was running, restart the timer
    if (timerStatusStr == 'running' && startedAt > 0) {
      _startTimer();
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timerMode', state.timerMode.name);
    await prefs.setString('timerStatus', state.timerStatus.name);
    await prefs.setString('timerPhase', state.timerPhase);
    await prefs.setInt('currentCycle', state.currentCycle);
    await prefs.setString('currentTask', state.currentTask);
    if (state.currentTaskId != null) {
      await prefs.setString('currentTaskId', state.currentTaskId!);
    }
    await prefs.setInt('totalSeconds', state.totalSeconds);
    await prefs.setInt('elapsedSeconds', state.elapsedSeconds);
    await prefs.setInt('startedAt', state.startedAt);
    await prefs.setInt('plannedDurationSeconds', state.plannedDurationSeconds);
    if (state.targetTime != null) {
      await prefs.setString('targetTime', state.targetTime!.toIso8601String());
    }
    await prefs.setInt('singleCoreMinDuration', state.singleCoreConfig.minDuration);
    await prefs.setInt('focusDuration', state.pomodoroConfig.focusDuration);
    await prefs.setInt('breakDuration', state.pomodoroConfig.breakDuration);
    await prefs.setInt('longBreakDuration', state.pomodoroConfig.longBreakDuration);
    await prefs.setInt('cyclesBeforeLongBreak', state.pomodoroConfig.cyclesBeforeLongBreak);
    await prefs.setBool('enableCycle', state.pomodoroConfig.enableCycle);
    await prefs.setBool('autoStartNext', state.pomodoroConfig.autoStartNext);
    await prefs.setBool('autoStartBreak', state.pomodoroConfig.autoStartBreak);
    await prefs.setBool('soundEnabled', state.soundEnabled);
    await prefs.setString('notificationDuration', state.notificationDuration);
    await prefs.setString('notificationTemplate', state.notificationTemplate);
    await prefs.setString('taskHistory', state.taskHistory.join(','));
  }

  void setTimerMode(TimerMode mode) {
    state = state.copyWith(timerMode: mode);
    _saveState();
  }

  void updateSingleCoreConfig(SingleCoreConfig config) {
    state = state.copyWith(singleCoreConfig: config);
    _saveState();
  }

  void updatePomodoroConfig(PomodoroConfig config) {
    state = state.copyWith(pomodoroConfig: config);
    _saveState();
  }

  void toggleSound() {
    state = state.copyWith(soundEnabled: !state.soundEnabled);
    _saveState();
  }

  void setNotificationDuration(String duration) {
    state = state.copyWith(notificationDuration: duration);
    _saveState();
  }

  void setNotificationTemplate(String template) {
    state = state.copyWith(notificationTemplate: template);
    _saveState();
  }

  void setCurrentTask(String task) {
    state = state.copyWith(currentTask: task);
    // 添加到历史记录
    final history = state.taskHistory.where((t) => t != task).toList();
    state = state.copyWith(taskHistory: [task, ...history].take(20).toList());
    _saveState();
  }

  void removeFromHistory(String task) {
    state = state.copyWith(taskHistory: state.taskHistory.where((t) => t != task).toList());
    _saveState();
  }

  void startFocus({String? taskTitle, String? taskId}) {
    // 停止铃声提醒
    TimerNotificationService.stopAlarm();

    final now = DateTime.now();
    int totalSeconds;
    DateTime? target;

    if (state.timerMode == TimerMode.singleCore) {
      final result = calculateSingleCoreTarget(state.singleCoreConfig.minDuration);
      totalSeconds = result.durationMinutes * 60;
      target = result.targetTime;
    } else {
      totalSeconds = state.pomodoroConfig.focusDuration * 60;
    }

    state = state.copyWith(
      timerStatus: TimerStatus.running,
      timerPhase: 'focus',
      currentTask: taskTitle ?? state.currentTask,
      currentTaskId: taskId ?? state.currentTaskId,
      totalSeconds: totalSeconds,
      elapsedSeconds: 0,
      targetTime: target,
      startedAt: now.millisecondsSinceEpoch,
      plannedDurationSeconds: totalSeconds,
    );

    _startTimer();
    _saveState();
  }

  void startBreak() {
    // 停止铃声提醒
    TimerNotificationService.stopAlarm();

    if (state.timerMode != TimerMode.pomodoro) return;

    final isLongBreak = state.currentCycle >= state.pomodoroConfig.cyclesBeforeLongBreak;
    final breakSeconds = (isLongBreak
            ? state.pomodoroConfig.longBreakDuration
            : state.pomodoroConfig.breakDuration) *
        60;

    state = state.copyWith(
      timerStatus: TimerStatus.running,
      timerPhase: isLongBreak ? 'long-break' : 'break',
      totalSeconds: breakSeconds,
      elapsedSeconds: 0,
      targetTime: null,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      plannedDurationSeconds: breakSeconds,
    );

    _startTimer();
    _saveState();
  }

  void skipBreak() {
    // 停止铃声提醒
    TimerNotificationService.stopAlarm();

    if (state.timerMode != TimerMode.pomodoro) return;
    if (state.timerPhase == 'idle' || state.timerPhase == 'focus') return;

    final shouldResetCycle = state.timerPhase == 'long-break';
    final focusSeconds = state.pomodoroConfig.focusDuration * 60;

    state = state.copyWith(
      timerStatus: TimerStatus.idle,
      timerPhase: 'focus',
      currentCycle: shouldResetCycle ? 0 : state.currentCycle,
      totalSeconds: focusSeconds,
      elapsedSeconds: 0,
      targetTime: null,
      startedAt: 0,
      plannedDurationSeconds: 0,
    );

    _stopTimer();
    _saveState();
  }

  void pauseFocus() {
    _stopTimer();
    // 暂停时也停止铃声，防止极端情况下铃声一直响
    TimerNotificationService.stopAlarm();
    state = state.copyWith(timerStatus: TimerStatus.paused);
    _saveState();
  }

  void resumeFocus() {
    // Recalculate startedAt to be current time minus already elapsed
    final now = DateTime.now();
    final elapsedBeforePause = state.elapsedSeconds;
    final newStartedAt = now.millisecondsSinceEpoch - (elapsedBeforePause * 1000);
    state = state.copyWith(
      timerStatus: TimerStatus.running,
      startedAt: newStartedAt,
    );
    _startTimer();
    _saveState();
  }

  void resetFocus() {
    // 停止铃声提醒
    TimerNotificationService.stopAlarm();

    // 如果计时器在运行且有startedAt，保存未完成的专注记录（>60秒）
    if (state.startedAt > 0 && state.timerPhase == 'focus' && state.timerStatus != TimerStatus.completed) {
      final elapsed = (DateTime.now().millisecondsSinceEpoch - state.startedAt) ~/ 1000;
      if (elapsed >= 60) {
        _saveFocusSession(false);
      }
    }

    _stopTimer();
    state = state.copyWith(
      timerStatus: TimerStatus.idle,
      timerPhase: 'focus',
      currentCycle: 0,
      totalSeconds: 0,
      elapsedSeconds: 0,
      targetTime: null,
      startedAt: 0,
      plannedDurationSeconds: 0,
    );
    _saveState();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.elapsedSeconds >= state.totalSeconds) {
        _onComplete();
      } else {
        state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onComplete() {
    _stopTimer();

    // 记录刚刚结束的阶段，用于通知显示
    final finishedPhase = state.timerPhase;

    // 番茄工作法逻辑
    if (state.timerMode == TimerMode.pomodoro) {
      if (state.timerPhase == 'focus') {
        // 专注阶段完成
        _saveFocusSession(true); // 保存完成的专注记录

        final newCycle = state.currentCycle + 1;
        final isLongBreak = state.pomodoroConfig.enableCycle &&
            newCycle >= state.pomodoroConfig.cyclesBeforeLongBreak;

        if (state.pomodoroConfig.autoStartBreak) {
          // 自动模式：直接开始休息
          startBreak();
          // 长休息后重置 cycle 计数
          if (isLongBreak) {
            state = state.copyWith(currentCycle: 0);
          }
        } else {
          // 手动模式：进入 completed 状态，等待用户点击开始休息
          state = state.copyWith(
            timerStatus: TimerStatus.completed,
            timerPhase: isLongBreak ? 'long-break' : 'break',
            currentCycle: isLongBreak ? 0 : newCycle,
          );
        }
      } else {
        // 休息阶段完成
        if (state.pomodoroConfig.autoStartNext) {
          // 自动开始下一轮专注
          startFocus();
        } else {
          // 手动模式：进入 idle 状态
          state = state.copyWith(
            timerStatus: TimerStatus.idle,
            timerPhase: 'focus',
          );
        }
      }
    } else {
      // 单核工作法完成
      _saveFocusSession(true);
      state = state.copyWith(timerStatus: TimerStatus.completed);
    }

    // 所有阶段结束后保存状态并触发铃声/系统通知
    _saveState();
    _triggerCompletionNotification(finishedPhase);
  }

  /// 计时结束时触发铃声 + Windows 通知中心 Toast + 应用内弹窗
  void _triggerCompletionNotification(String finishedPhase) {
    final task = state.currentTask.isNotEmpty ? state.currentTask : null;
    final template = state.notificationTemplate;
    // 将模板中的 {task} 占位符替换为实际任务名
    final body = task != null
        ? template.replaceAll('{task}', task)
        : template.replaceAll('！{task}', '！').replaceAll('{task}', '');

    // 根据刚刚结束的阶段决定通知标题
    String title;
    if (finishedPhase == 'focus') {
      title = '🎉 专注完成！';
    } else if (finishedPhase == 'long-break') {
      title = '☕ 长休息结束';
    } else {
      title = '⏰ 休息结束';
    }

    // 异步触发，不阻塞计时器状态更新
    TimerNotificationService.triggerAlarm(
      title: title,
      body: body,
      soundEnabled: state.soundEnabled,
      phase: finishedPhase,
      duration: state.notificationDuration,
    );
  }

  void _saveFocusSession(bool completed) async {
    if (state.startedAt == 0) return;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - state.startedAt) ~/ 1000;
    if (elapsed < 60) return;

    await AppDatabase.addFocusSession(
      taskId: state.currentTaskId,
      taskTitle: state.currentTask.isNotEmpty ? state.currentTask : '（未设置）',
      timerMode: state.timerMode.name,
      durationSeconds: elapsed,
      plannedDurationSeconds: state.plannedDurationSeconds,
      completed: completed,
      startedAt: state.startedAt,
      completedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _ref.read(sessionUpdateProvider.notifier).state++;
    
    // 触发同步
    if (SyncService.isLoggedIn) {
      _ref.read(taskProvider.notifier).sync();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

final timerProvider = StateNotifierProvider<TimerNotifier, TimerState>((ref) {
  return TimerNotifier(ref);
});

final sessionUpdateProvider = StateProvider<int>((ref) => 0);