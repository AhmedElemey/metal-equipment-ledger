import 'package:flutter/material.dart';

/// Steel blue + safety orange — the colours of a metal workshop.
abstract final class AppColors {
  static const steel = Color(0xFF263845);
  static const orange = Color(0xFFE8772E);
  static const sale = Color(0xFF2E7D32);
  static const purchase = Color(0xFF1565C0);
  static const danger = Color(0xFFC62828);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.steel,
    primary: AppColors.steel,
    secondary: AppColors.orange,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: const Color(0xFFF4F5F7),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.steel,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
  );
}
