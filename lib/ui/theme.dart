import 'package:flutter/material.dart';

abstract final class GiggleColors {
  static const night = Color(0xFF1A1036);
  static const plum = Color(0xFF3B1E7A);
  static const violet = Color(0xFF7C4DFF);
  static const sun = Color(0xFFFFD43B);
  static const coral = Color(0xFFFF6B6B);
  static const card = Color(0x1FFFFFFF);
}

ThemeData giggleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GiggleColors.violet,
    brightness: Brightness.dark,
    primary: GiggleColors.violet,
    secondary: GiggleColors.sun,
    surface: GiggleColors.night,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: GiggleColors.night,
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// The app-wide backdrop, drawn in code (no image needed).
const BoxDecoration giggleBackdrop = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [GiggleColors.plum, GiggleColors.night],
  ),
);
