import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/core/utils/app_time.dart';

class AiContextBuilder {
  static String buildSystemPrompt({
    required List<TaskItem> allTasks,
    required List<TaskList> lists,
    required DateTime now,
    String customPrompt = '',
    bool datedListEnabled = false,
    String datedListFormat = 'yyyyMMdd',
    bool reminderOnCreate = false,
  }) {
    final todayStr = _formatDate(now);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final buf = StringBuffer();

    buf.writeln('你是一个任务管理助手，帮助用户管理他们的任务清单。');
    buf.writeln();
    buf.writeln('## 当前时间');
    buf.writeln('日期: $todayStr ($_weekdayName(now))');
    buf.writeln('时间: $timeStr');
    buf.writeln(
        '时区: ${AppTime.label(AppTime.mode)} (${AppTime.offsetLabelForMode(AppTime.mode)})');
    buf.writeln('所有时间安排必须不早于当前时间。');
    buf.writeln();

    // Lists
    buf.writeln('## 任务清单');
    for (final list in lists) {
      final marker = list.isSystem ? '[系统]' : '[自定义]';
      buf.writeln('- $marker ${list.name} (ID: ${list.id})');
    }
    buf.writeln();

    // Today's tasks
    final todayTasks = allTasks.where((t) {
      if (t.dueDate == null) return t.isMyDay;
      return t.dueDate == todayStr || t.isMyDay;
    }).toList();

    if (todayTasks.isNotEmpty) {
      buf.writeln('## 今日任务');
      for (final t in todayTasks) {
        buf.writeln(_formatTaskLine(t));
      }
      buf.writeln();
    }

    // Upcoming tasks (next 7 days, not today)
    final weekEnd = _formatDate(now.add(const Duration(days: 7)));
    final weekTasks = allTasks.where((t) {
      if (t.dueDate == null || t.dueDate == todayStr) return false;
      return t.dueDate!.compareTo(todayStr) > 0 &&
          t.dueDate!.compareTo(weekEnd) <= 0;
    }).toList();

    if (weekTasks.isNotEmpty) {
      buf.writeln('## 未来 7 天任务');
      for (final t in weekTasks) {
        buf.writeln(_formatTaskLine(t));
      }
      buf.writeln();
    }

    // Other incomplete tasks (no due date, not today)
    final otherTasks = allTasks.where((t) {
      if (t.completed) return false;
      if (t.dueDate != null) return false;
      if (t.isMyDay) return false;
      return true;
    }).toList();

    if (otherTasks.isNotEmpty && otherTasks.length <= 30) {
      buf.writeln('## 其他未完成任务');
      for (final t in otherTasks.take(30)) {
        buf.writeln('- ${t.title} (ID: ${t.id})');
      }
      if (otherTasks.length > 30) {
        buf.writeln('- ... 还有 ${otherTasks.length - 30} 个任务');
      }
      buf.writeln();
    }

    // Constraints
    buf.writeln('## 约束规则');
    buf.writeln('1. 时间安排不得早于当前时间 ($timeStr)');
    buf.writeln('2. 不得修改应用设置相关的任何内容');
    buf.writeln('3. 删除任务前请先确认，并在摘要中说明原因');
    buf.writeln('4. 创建任务时请合理安排时间，避免时间段重叠');
    buf.writeln('5. 如果需要修改的任务 ID 不确定，先向用户确认');
    buf.writeln('6. 当用户描述的任务带有时间信息时（如"明天下午3点"），应计算出正确的日期和时间');
    buf.writeln('7. 使用中文与用户交流');
    buf.writeln(
        '8. 重要：reminderAt=任务开始时间，dueDate/dueTime=任务截止时间（结束时间），两者不是同一个时间。截止时间 = 开始时间 + expectedMinutes。');
    buf.writeln(
        '9. 当用户要求"安排今天/规划今天/排日程"时，必须输出可执行时间表：每个被安排的任务都要有开始时间 reminderAt、预计时长 expectedMinutes、结束时间 dueDate/dueTime。');
    buf.writeln('10. 安排日程时必须避免重叠；任务之间默认保留 0-10 分钟间隔，并根据任务难度、脑力消耗和时间紧张程度调整。');
    buf.writeln('11. 如果用户偏好中包含禁止时间段（如"不要在19到20点安排任务"），该时间段视为硬性不可用区间，不得安排任务。');
    buf.writeln('12. 如果任务太大、太难或当天没有连续时间，应拆分成多个清晰的小任务，并分别安排开始时间和持续时长。');

    // Custom user preferences
    if (customPrompt.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 用户偏好（请严格遵守）');
      buf.writeln(customPrompt);
      buf.writeln();
      buf.writeln('执行用户偏好时的优先级：');
      buf.writeln('- 将用户偏好当作日程安排的硬约束和排序依据，除非与当前时间或任务截止时间冲突。');
      buf.writeln('- 如果无法完全满足某条偏好，必须在回复中明确说明原因，不要静默违反。');
      buf.writeln('- 优先把高挑战学习/工作安排在早上，把运动安排在用户偏好的时段，把复盘、放松、杂事安排在晚上。');
      buf.writeln('- 中午到下午的安排应更松散，允许午睡或低强度任务，避免连续高脑力任务。');
    }

    // Dated list configuration
    if (datedListEnabled) {
      final dateStr = _formatDateWith(now, datedListFormat);
      buf.writeln();
      buf.writeln('## 日期清单模式（已启用）');
      buf.writeln('当前日期清单名称: $dateStr');
      buf.writeln('日期格式: $datedListFormat');
      buf.writeln('规则: 创建任务时，必须使用清单名 "$dateStr" 作为 listId。如果该清单不存在，系统会自动创建。');
      buf.writeln(
          '不要使用系统清单（system-my-day/system-all-tasks/system-important），请使用日期清单。');
      buf.writeln(
          '除非用户明确要求添加到"我的一天"，否则 create_task 时 isMyDay 必须为 false 或省略，且不要调用 add_to_my_day。');
      buf.writeln('如果你需要先创建清单，请创建名为 "$dateStr" 的清单，然后继续把任务创建到该清单。');
    }

    // Reminder on create
    if (reminderOnCreate) {
      buf.writeln();
      buf.writeln('## 任务开始时间提醒（已启用）');
      buf.writeln('重要字段区分：');
      buf.writeln('- reminderAt = 任务开始时间（用户何时开始做），ISO 8601 格式');
      buf.writeln(
          '- dueDate + dueTime = 任务截止时间（用户何时必须完成），截止时间 = 开始时间 + expectedMinutes');
      buf.writeln('规则：');
      buf.writeln('1. 创建任务时必须设置 reminderAt 为任务的开始时间');
      buf.writeln(
          '2. 必须根据开始时间 + expectedMinutes 计算出正确的截止时间（dueDate + dueTime）');
      buf.writeln('3. 如果用户没有明确截止时间，则用开始时间 + expectedMinutes 推算');
      buf.writeln(
          '例如：用户说"22:20开始，1.5小时"，则 reminderAt = "$todayStr"T"22:20:00"，expectedMinutes = 90，dueDate = "$todayStr"，dueTime = "23:50"。');
      buf.writeln('这3个字段必须同时存在，这是强制要求。');
    }

    return buf.toString();
  }

  static String _formatTaskLine(TaskItem t) {
    final parts = <String>['-'];
    if (t.completed) parts.add('[已完成]');
    if (t.isImportant) parts.add('[重要]');
    parts.add(t.title);
    if (t.dueDate != null) {
      parts.add('截止: ${t.dueDate}');
      if (t.dueTime != null) parts.add(t.dueTime!);
    }
    if (t.isMyDay) parts.add('[我的一天]');
    if (t.reminderAt != null) {
      final reminderDate = AppTime.fromMillisecondsSinceEpoch(t.reminderAt!);
      parts.add('提醒: ${_formatDateTime(reminderDate)}');
    }
    if (t.recurrenceConfig != null) parts.add('[重复]');
    if (t.expectedMinutes != null) parts.add('预计${t.expectedMinutes}分钟');
    parts.add('(ID: ${t.id})');
    return parts.join(' ');
  }
}

String _formatDateWith(DateTime dt, String format) {
  return format
      .replaceAll('yyyy', dt.year.toString())
      .replaceAll('MM', dt.month.toString().padLeft(2, '0'))
      .replaceAll('dd', dt.day.toString().padLeft(2, '0'))
      .replaceAll('yy', (dt.year % 100).toString().padLeft(2, '0'))
      .replaceAll('M', dt.month.toString())
      .replaceAll('d', dt.day.toString());
}

String _formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime dt) =>
    '${_formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

String _weekdayName(DateTime dt) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[dt.weekday - 1];
}
