import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';

void main() {
  group('SingleCoreConfig', () {
    test('default minDuration is 25', () {
      const config = SingleCoreConfig();
      expect(config.minDuration, 25);
    });

    test('copyWith updates minDuration', () {
      const config = SingleCoreConfig(minDuration: 30);
      final updated = config.copyWith(minDuration: 45);
      expect(updated.minDuration, 45);
    });

    test('copyWith preserves unchanged values', () {
      const config = SingleCoreConfig(minDuration: 30);
      final updated = config.copyWith();
      expect(updated.minDuration, 30);
    });
  });

  group('PomodoroConfig', () {
    test('default values are correct', () {
      const config = PomodoroConfig();
      expect(config.focusDuration, 25);
      expect(config.breakDuration, 5);
      expect(config.longBreakDuration, 15);
      expect(config.cyclesBeforeLongBreak, 4);
      expect(config.enableCycle, false);
      expect(config.maxCycles, 0);
      expect(config.autoStartNext, false);
      expect(config.autoStartBreak, false);
    });

    test('copyWith updates values correctly', () {
      const config = PomodoroConfig();
      final updated = config.copyWith(
        focusDuration: 30,
        breakDuration: 10,
        longBreakDuration: 20,
        enableCycle: true,
      );
      expect(updated.focusDuration, 30);
      expect(updated.breakDuration, 10);
      expect(updated.longBreakDuration, 20);
      expect(updated.enableCycle, true);
    });

    test('copyWith preserves unchanged values', () {
      const config = PomodoroConfig(focusDuration: 30);
      final updated = config.copyWith(breakDuration: 10);
      expect(updated.focusDuration, 30);
      expect(updated.breakDuration, 10);
    });
  });

  group('TimerState', () {
    test('default values are correct', () {
      final state = TimerState();
      expect(state.timerMode, TimerMode.singleCore);
      expect(state.timerStatus, TimerStatus.idle);
      expect(state.currentTask, '');
      expect(state.currentTaskId, null);
      expect(state.taskHistory, isEmpty);
      expect(state.totalSeconds, 0);
      expect(state.elapsedSeconds, 0);
      expect(state.timerPhase, 'focus');
      expect(state.currentCycle, 0);
      expect(state.notificationDuration, 'long');
      expect(state.soundEnabled, true);
    });

    test('remainingSeconds calculates correctly', () {
      final state = TimerState(totalSeconds: 100, elapsedSeconds: 30);
      expect(state.remainingSeconds, 70);
    });

    test('remainingSeconds never negative', () {
      final state = TimerState(totalSeconds: 100, elapsedSeconds: 150);
      expect(state.remainingSeconds, 0);
    });

    test('progress calculates correctly', () {
      final state = TimerState(totalSeconds: 100, elapsedSeconds: 25);
      expect(state.progress, 0.25);
    });

    test('progress is 0 when totalSeconds is 0', () {
      final state = TimerState(totalSeconds: 0, elapsedSeconds: 0);
      expect(state.progress, 0.0);
    });

    test('formattedTime formats correctly', () {
      final state = TimerState(totalSeconds: 1500, elapsedSeconds: 0); // 25:00
      expect(state.formattedTime, '25:00');
    });

    test('formattedTime shows remaining time', () {
      final state = TimerState(totalSeconds: 1500, elapsedSeconds: 900); // 10:00 remaining
      expect(state.formattedTime, '10:00');
    });

    test('copyWith updates all fields correctly', () {
      final state = TimerState();
      final updated = state.copyWith(
        timerMode: TimerMode.pomodoro,
        timerStatus: TimerStatus.running,
        currentTask: 'Test Task',
        currentTaskId: 'task-123',
        taskHistory: ['Task 1', 'Task 2'],
        totalSeconds: 1500,
        elapsedSeconds: 0,
        timerPhase: 'focus',
        currentCycle: 1,
        notificationDuration: 'persistent',
      );

      expect(updated.timerMode, TimerMode.pomodoro);
      expect(updated.timerStatus, TimerStatus.running);
      expect(updated.currentTask, 'Test Task');
      expect(updated.currentTaskId, 'task-123');
      expect(updated.taskHistory, ['Task 1', 'Task 2']);
      expect(updated.totalSeconds, 1500);
      expect(updated.elapsedSeconds, 0);
      expect(updated.timerPhase, 'focus');
      expect(updated.currentCycle, 1);
      expect(updated.notificationDuration, 'persistent');
    });

    test('copyWith preserves unchanged fields', () {
      final state = TimerState(
        currentTask: 'Original Task',
        totalSeconds: 100,
      );
      final updated = state.copyWith(totalSeconds: 200);
      expect(updated.currentTask, 'Original Task');
      expect(updated.totalSeconds, 200);
    });

    test('copyWith preserves taskHistory when not provided', () {
      final state = TimerState(taskHistory: ['Task 1', 'Task 2']);
      final updated = state.copyWith(currentTask: 'New Task');
      expect(updated.taskHistory, ['Task 1', 'Task 2']);
    });

    test('copyWith updates taskHistory when provided', () {
      final state = TimerState(taskHistory: ['Task 1', 'Task 2']);
      final updated = state.copyWith(taskHistory: ['Task 3']);
      expect(updated.taskHistory, ['Task 3']);
    });
  });

  group('TimerMode enum', () {
    test('has correct values', () {
      expect(TimerMode.values.length, 2);
      expect(TimerMode.values, contains(TimerMode.singleCore));
      expect(TimerMode.values, contains(TimerMode.pomodoro));
    });
  });

  group('TimerStatus enum', () {
    test('has correct values', () {
      expect(TimerStatus.values.length, 4);
      expect(TimerStatus.values, contains(TimerStatus.idle));
      expect(TimerStatus.values, contains(TimerStatus.running));
      expect(TimerStatus.values, contains(TimerStatus.paused));
      expect(TimerStatus.values, contains(TimerStatus.completed));
    });
  });
}
