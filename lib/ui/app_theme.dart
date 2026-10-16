import 'package:flutter/material.dart';

class AppTheme {
  static const Color accent = Color(0xFFA78BFA);

  static Color get background => Color.lerp(Colors.black, accent, 0.075)!;

  static Color get surface => Color.lerp(Colors.black, accent, 0.11)!;

  static Color get surfaceVariant => Color.lerp(Colors.black, accent, 0.22)!;

  static Color get textSecondary => Color.lerp(Colors.white, accent, 0.35)!;

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Quicksand',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: surfaceVariant,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? accent
                : textSecondary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        prefixIconColor: accent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        textColor: colorScheme.onSurface,
        subtitleTextStyle: TextStyle(color: textSecondary),
      ),
      dividerColor: surfaceVariant,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceVariant,
      ),
    );
  }
}
