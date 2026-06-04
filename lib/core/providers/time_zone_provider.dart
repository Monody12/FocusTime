import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';

class TimeZoneNotifier extends StateNotifier<AppTimeZoneMode> {
  TimeZoneNotifier() : super(AppTimeZoneMode.system) {
    _load();
  }

  Future<void> _load() async {
    final value = await AppDatabase.getSetting(AppTime.settingKey);
    final mode = AppTime.modeFromValue(value);
    AppTime.configure(mode);
    state = mode;
  }

  Future<void> setMode(AppTimeZoneMode mode) async {
    AppTime.configure(mode);
    state = mode;
    await AppDatabase.setSetting(
        AppTime.settingKey, AppTime.valueFromMode(mode));
    SyncService.triggerBackgroundSync();
  }
}

final timeZoneProvider =
    StateNotifierProvider<TimeZoneNotifier, AppTimeZoneMode>((ref) {
  return TimeZoneNotifier();
});
