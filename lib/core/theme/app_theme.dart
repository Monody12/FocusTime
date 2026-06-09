import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // 深色主题：深海蓝绿基底，保留旧版的沉浸感和计时工具气质。
  static const darkBackground = Color(0xFF101923);
  static const darkSidebar = Color(0xFF132236);
  static const darkSurface = Color(0xFF1A2A3D);
  static const darkSurfaceElevated = Color(0xFF213650);
  static const darkBorder = Color(0xFF2F4D68);
  static const darkAccent = Color(0xFF67D36E);
  static const darkAccentSecondary = Color(0xFF4FC3F7);
  static const darkSuccess = Color(0xFF67D36E);
  static const darkWarning = Color(0xFFFFB84D);
  static const darkText = Color(0xFFEAF1F7);
  static const darkTextSecondary = Color(0xFFA8B5C3);

  // 浅色主题
  static const lightBackground = Color(0xFFF4F8F7);
  static const lightSidebar = Color(0xFFEAF4F2);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFE7F4F0);
  static const lightBorder = Color(0xFFC7DCD7);
  static const lightAccent = Color(0xFF1F9D55);
  static const lightAccentSecondary = Color(0xFF0284C7);
  static const lightSuccess = Color(0xFF1F9D55);
  static const lightWarning = Color(0xFFB7791F);
  static const lightText = Color(0xFF18303D);
  static const lightTextSecondary = Color(0xFF60727D);
}

class AppTheme {
  // 使用 Noto Sans SC (思源黑体) 作为全局字体，确保中英文粗细一致且美观
  // 该字体由 Google 提供，完美支持中文各种字重。

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // 使用 Noto Sans SC 覆盖所有文本样式
    textTheme: GoogleFonts.notoSansScTextTheme(ThemeData.dark().textTheme),
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.darkSurface,
      primary: AppColors.darkAccent,
      secondary: AppColors.darkAccentSecondary,
      onSurface: AppColors.darkText,
    ),
    cardTheme: const CardTheme(
      color: AppColors.darkSurface,
      elevation: 4,
      shadowColor: Color(0x66071118),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.darkBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.darkText,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkAccent, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.darkAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.darkAccent,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.darkAccent;
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.darkAccent.withOpacity(0.5);
        }
        return Colors.grey.withOpacity(0.3);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkAccent,
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    // 使用 Noto Sans SC 覆盖所有文本样式
    textTheme: GoogleFonts.notoSansScTextTheme(ThemeData.light().textTheme),
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: const ColorScheme.light(
      surface: AppColors.lightSurface,
      primary: AppColors.lightAccent,
      secondary: AppColors.lightAccentSecondary,
      onSurface: AppColors.lightText,
    ),
    cardTheme: const CardTheme(
      color: AppColors.lightSurface,
      elevation: 2,
      shadowColor: Color(0x1F18303D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.lightBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBackground,
      foregroundColor: AppColors.lightText,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.lightBorder),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightAccent, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.lightAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.lightAccent,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.lightAccent;
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.lightAccent.withOpacity(0.5);
        }
        return Colors.grey.withOpacity(0.3);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.lightAccent,
        side: const BorderSide(color: AppColors.lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
