import 'package:flutter/material.dart';

abstract final class FloatTheme {
  static const paper = Color(0xFFF8F8F5);
  static const ink = Color(0xFF111111);
  static const mutedInk = Color(0xFF666662);
  static const line = Color(0xFFD9D9D3);
  static const soft = Color(0xFFF0F0EC);

  static ThemeData get data => ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: ink,
      onPrimary: Colors.white,
      secondary: ink,
      onSecondary: Colors.white,
      surface: paper,
      onSurface: ink,
      outline: line,
    ),
    scaffoldBackgroundColor: paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ink, width: 1.4),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? ink : line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  static const shortMotion = Duration(milliseconds: 180);
  static const gentleCurve = Curves.easeOutCubic;
}
