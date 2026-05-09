String formatTime(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

({int durationMinutes, DateTime targetTime}) calculateSingleCoreTarget(int minDuration) {
  final now = DateTime.now();
  final minute = now.minute;

  // 找到下一个整点或半点
  DateTime nextTarget;
  if (minute < 30) {
    nextTarget = DateTime(now.year, now.month, now.day, now.hour, 30);
  } else {
    nextTarget = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
  }

  int durationMinutes = nextTarget.difference(now).inMinutes;

  // 如果不足最小时长，继续跳到下一个整点/半点
  while (durationMinutes < minDuration) {
    nextTarget = nextTarget.add(const Duration(minutes: 30));
    durationMinutes = nextTarget.difference(now).inMinutes;
  }

  return (durationMinutes: durationMinutes, targetTime: nextTarget);
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatTimeOfDay(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
