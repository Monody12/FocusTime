import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.accent,
    required this.accentSecondary,
    required this.success,
    required this.warning,
    required this.text,
    required this.textSecondary,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color accent;
  final Color accentSecondary;
  final Color success;
  final Color warning;
  final Color text;
  final Color textSecondary;

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? accent,
    Color? accentSecondary,
    Color? success,
    Color? warning,
    Color? text,
    Color? textSecondary,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

class AppThemeScheme {
  const AppThemeScheme({
    required this.id,
    required this.label,
    required this.light,
    required this.dark,
  });

  final String id;
  final String label;
  final AppThemeColors light;
  final AppThemeColors dark;
}

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

  static const darkThemeColors = AppThemeColors(
    background: darkBackground,
    sidebar: darkSidebar,
    surface: darkSurface,
    surfaceElevated: darkSurfaceElevated,
    border: darkBorder,
    accent: darkAccent,
    accentSecondary: darkAccentSecondary,
    success: darkSuccess,
    warning: darkWarning,
    text: darkText,
    textSecondary: darkTextSecondary,
  );

  static const lightThemeColors = AppThemeColors(
    background: lightBackground,
    sidebar: lightSidebar,
    surface: lightSurface,
    surfaceElevated: lightSurfaceElevated,
    border: lightBorder,
    accent: lightAccent,
    accentSecondary: lightAccentSecondary,
    success: lightSuccess,
    warning: lightWarning,
    text: lightText,
    textSecondary: lightTextSecondary,
  );
}

extension AppThemeContext on BuildContext {
  AppThemeColors get appColors {
    final extensionColors = Theme.of(this).extension<AppThemeColors>();
    if (extensionColors != null) return extensionColors;
    return Theme.of(this).brightness == Brightness.dark
        ? AppColors.darkThemeColors
        : AppColors.lightThemeColors;
  }
}

class AppTheme {
  // 使用 Noto Sans SC (思源黑体) 作为全局字体，确保中英文粗细一致且美观
  // 该字体由 Google 提供，完美支持中文各种字重。
  static const blueAmberLightColors = AppThemeColors(
    background: Color(0xFFF8FAFC),
    sidebar: Color(0xFFEFF6FF),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    border: Color(0xFFCBDDEB),
    accent: Color(0xFF2563EB),
    accentSecondary: Color(0xFF0D9488),
    success: Color(0xFF16A34A),
    warning: Color(0xFF7C3AED),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6B7D),
  );

  static const blueAmberDarkColors = AppThemeColors(
    background: Color(0xFF0F172A),
    sidebar: Color(0xFF111D31),
    surface: Color(0xFF172338),
    surfaceElevated: Color(0xFF1D2E49),
    border: Color(0xFF334A67),
    accent: Color(0xFF60A5FA),
    accentSecondary: Color(0xFF2DD4BF),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFA78BFA),
    text: Color(0xFFEFF6FF),
    textSecondary: Color(0xFFAFC0D3),
  );

  static const blueAmberScheme = AppThemeScheme(
    id: 'blueAmber',
    label: '蓝青',
    light: blueAmberLightColors,
    dark: blueAmberDarkColors,
  );

  static const greenScheme = AppThemeScheme(
    id: 'greenImmersive',
    label: '绿色沉浸',
    light: AppColors.lightThemeColors,
    dark: AppColors.darkThemeColors,
  );

  static const defaultScheme = blueAmberScheme;

  static const List<AppThemeScheme> schemes = [
    blueAmberScheme,
    greenScheme,
  ];

  static AppThemeScheme schemeById(String id) {
    return schemes.firstWhere(
      (scheme) => scheme.id == id,
      orElse: () => defaultScheme,
    );
  }

  static ThemeData darkThemeFor(AppThemeScheme scheme) => buildTheme(
        colors: scheme.dark,
        brightness: Brightness.dark,
      );

  static ThemeData lightThemeFor(AppThemeScheme scheme) => buildTheme(
        colors: scheme.light,
        brightness: Brightness.light,
      );

  static ThemeData darkTheme = darkThemeFor(defaultScheme);

  static ThemeData lightTheme = lightThemeFor(defaultScheme);

  static ThemeData buildTheme({
    required AppThemeColors colors,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // 使用 Noto Sans SC 覆盖所有文本样式
      textTheme: GoogleFonts.notoSansScTextTheme(baseTheme.textTheme),
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: isDark ? colors.background : Colors.white,
        secondary: colors.accentSecondary,
        onSecondary: isDark ? colors.background : Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: colors.surface,
        onSurface: colors.text,
      ),
      extensions: [colors],
      cardTheme: CardTheme(
        color: colors.surface,
        elevation: isDark ? 4 : 2,
        shadowColor: isDark ? const Color(0x66071118) : const Color(0x1F18303D),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: colors.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: isDark ? colors.background : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accent;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accent.withOpacity(0.5);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accent,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
