import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Notifica a MaterialApp cuando cambia la apariencia global.
  static final ChangeNotifier notifier = ChangeNotifier();

  static const Color defaultAccent = Color(0xFF6750A4);
  static const bool defaultDarkTheme = true;

  static bool _isDarkTheme = defaultDarkTheme;
  static Color _accent = defaultAccent;

  static bool get isDarkTheme => _isDarkTheme;
  static Color get accent => _accent;

  static Color get background => _isDarkTheme
      ? Color.lerp(Colors.black, _accent, 0.075)!
      : Color.lerp(Colors.white, _accent, 0.035)!;

  static Color get surface => _isDarkTheme
      ? Color.lerp(Colors.black, _accent, 0.11)!
      : Color.lerp(Colors.white, _accent, 0.06)!;

  static Color get surfaceVariant => _isDarkTheme
      ? Color.lerp(Colors.black, _accent, 0.22)!
      : Color.lerp(Colors.white, _accent, 0.18)!;

  static Color get textSecondary => _isDarkTheme
      ? Color.lerp(Colors.white, _accent, 0.35)!
      : Color.lerp(Colors.black, _accent, 0.30)!;

  /// Actualiza la apariencia global y reconstruye los widgets suscritos.
  static void updateAppearance({
    required bool darkTheme,
    required Color accentColor,
  }) {
    if (_isDarkTheme == darkTheme && _accent == accentColor) {
      return;
    }

    _isDarkTheme = darkTheme;
    _accent = accentColor;
    notifier.notifyListeners();
  }

  /// Tema actualmente seleccionado.
  static ThemeData get current => _isDarkTheme ? dark : light;

  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData get light => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final currentBackground = isDark
        ? Color.lerp(Colors.black, _accent, 0.075)!
        : Color.lerp(Colors.white, _accent, 0.035)!;

    final currentSurface = isDark
        ? Color.lerp(Colors.black, _accent, 0.11)!
        : Color.lerp(Colors.white, _accent, 0.06)!;

    final currentSurfaceVariant = isDark
        ? Color.lerp(Colors.black, _accent, 0.22)!
        : Color.lerp(Colors.white, _accent, 0.18)!;

    final currentTextSecondary = isDark
        ? Color.lerp(Colors.white, _accent, 0.35)!
        : Color.lerp(Colors.black, _accent, 0.30)!;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: brightness,
      surface: currentSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Quicksand',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: currentBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: currentSurface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: currentSurface,
        indicatorColor: currentSurfaceVariant,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? _accent
                : currentTextSecondary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: currentSurface,
        prefixIconColor: _accent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _accent, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: _accent,
        textColor: colorScheme.onSurface,
        subtitleTextStyle: TextStyle(color: currentTextSecondary),
      ),
      dividerColor: currentSurfaceVariant,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: currentSurfaceVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _accent : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _accent,
        thumbColor: _accent,
        overlayColor: _accent.withValues(alpha: 0.12),
        inactiveTrackColor: currentSurfaceVariant,
      ),
    );
  }
}
