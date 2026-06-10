import 'package:flutter/material.dart';

class AppIconSizes {
  static const double nav = 18;
  static const double action = 18;
  static const double compact = 16;
  static const double status = 14;
  static const double empty = 48;
}

class AppIconSpacing {
  static const double labelGap = 12;
  static const double compactGap = 6;
}

class AppIcons {
  static const IconData menu = Icons.menu;
  static const IconData lightMode = Icons.light_mode;
  static const IconData darkMode = Icons.dark_mode;
  static const IconData ai = Icons.smart_toy_outlined;
  static const IconData settings = Icons.settings;
  static const IconData close = Icons.close;
  static const IconData back = Icons.arrow_back;
  static const IconData previous = Icons.chevron_left;
  static const IconData next = Icons.chevron_right;
  static const IconData arrowForward = Icons.arrow_forward;
  static const IconData add = Icons.add;

  static const IconData myDay = Icons.wb_sunny_outlined;
  static const IconData important = Icons.star_border;
  static const IconData importantFilled = Icons.star;
  static const IconData tasks = Icons.checklist_outlined;
  static const IconData list = Icons.folder_outlined;
  static const IconData listAdd = Icons.add;
  static const IconData listReceive = Icons.add_circle_outline;

  static const IconData addTask = Icons.add;
  static const IconData taskDone = Icons.check;
  static const IconData taskComplete = Icons.check_circle_outline;
  static const IconData taskIncomplete = Icons.radio_button_unchecked;
  static const IconData schedule = Icons.schedule;
  static const IconData reminder = Icons.notifications_none;
  static const IconData reminderActive = Icons.notifications_active;
  static const IconData calendar = Icons.calendar_today_outlined;
  static const IconData today = Icons.today_outlined;
  static const IconData tomorrow = Icons.next_week_outlined;
  static const IconData move = Icons.move_to_inbox_outlined;
  static const IconData archive = Icons.archive_outlined;
  static const IconData restore = Icons.unarchive_outlined;
  static const IconData delete = Icons.delete_outline;
  static const IconData deleteForever = Icons.delete_forever_outlined;
  static const IconData edit = Icons.edit_outlined;
  static const IconData editNote = Icons.edit_note;
  static const IconData repeat = Icons.repeat;
  static const IconData reorder = Icons.reorder;
  static const IconData playlistAdd = Icons.playlist_add;
  static const IconData playlistRemove = Icons.playlist_remove;
  static const IconData help = Icons.help_outline;
  static const IconData flag = Icons.flag_outlined;

  static const IconData focus = Icons.track_changes;
  static const IconData timer = Icons.timer_outlined;
  static const IconData pause = Icons.pause;
  static const IconData play = Icons.play_arrow;
  static const IconData reset = Icons.refresh;
  static const IconData breakTime = Icons.free_breakfast_outlined;
  static const IconData expandMore = Icons.arrow_drop_down;
  static const IconData expandLess = Icons.arrow_drop_up;
  static const IconData recent = Icons.history;

  static const IconData copy = Icons.copy;
  static const IconData send = Icons.send_rounded;
  static const IconData tune = Icons.tune;
  static const IconData preview = Icons.preview;
  static const IconData key = Icons.key;
  static const IconData user = Icons.person;
  static const IconData visible = Icons.visibility;
  static const IconData hidden = Icons.visibility_off;
  static const IconData emptyTasks = Icons.assignment_outlined;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.color,
    this.size = AppIconSizes.action,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Icon(icon, size: size, color: color),
    );
  }
}
