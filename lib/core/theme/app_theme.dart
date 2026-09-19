import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData buildBoraTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.green,
    surface: AppColors.night,
    error: AppColors.danger,
  );

  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.night,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.text,
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.2),
      titleLarge:
          const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
      bodyLarge: const TextStyle(fontSize: 16, color: AppColors.textMuted, height: 1.5),
      bodyMedium: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.45),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: Color(0x80CBD5E1)),
      enabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.green),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
  );
}
