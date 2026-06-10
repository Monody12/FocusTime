import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('themeMode') ?? 'system';
    state = _parseThemeMode(themeStr);
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeModeToString(mode));
  }

  void toggleTheme() {
    if (state == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeSchemeNotifier extends StateNotifier<AppThemeScheme> {
  ThemeSchemeNotifier() : super(AppTheme.defaultScheme) {
    _loadThemeScheme();
  }

  Future<void> _loadThemeScheme() async {
    final prefs = await SharedPreferences.getInstance();
    final schemeId =
        prefs.getString('themeSchemeId') ?? AppTheme.defaultScheme.id;
    state = AppTheme.schemeById(schemeId);
  }

  Future<void> setThemeScheme(String schemeId) async {
    final scheme = AppTheme.schemeById(schemeId);
    state = scheme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeSchemeId', scheme.id);
  }
}

final themeSchemeProvider =
    StateNotifierProvider<ThemeSchemeNotifier, AppThemeScheme>((ref) {
  return ThemeSchemeNotifier();
});
