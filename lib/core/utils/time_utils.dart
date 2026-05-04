String formatTime(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

({int durationMinutes, DateTime targetTime}) calculateSingleCoreTarget(int minDuration) {
  final now = DateTime.now();
  final minute = now.minute;
  final second = now.second;

  // 计算当前时间已经过去的秒数
  final elapsedSeconds = minute * 60 + second;

  // 找到最近的整点或半点 (00:00 或 00:30)
  int targetMinute;
  if (minute < 30) {
    targetMinute = 30;
  } else {
    // minute >= 30, 找到下一个整点
    targetMinute = 60;
  }

  final targetTime = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour + (minute >= 30 ? 1 : 0),
    targetMinute == 60 ? 0 : targetMinute,
  );

  final durationMinutes = targetTime.difference(now).inMinutes;

  // 如果计算出的时间小于最小时间，调整到最小时间
  final adjustedDuration = durationMinutes < minDuration ? minDuration : durationMinutes;

  final actualTargetTime = now.add(Duration(minutes: adjustedDuration));

  return (durationMinutes: adjustedDuration, targetTime: actualTargetTime);
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatTimeOfDay(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}