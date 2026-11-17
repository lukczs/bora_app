import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'tokens.dart';

ThemeData buildBoraTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: Brightness.dark).copyWith(
    primary: AppColors.green,
    onPrimary: AppColors.night,
    surface: AppColors.night,
    surfaceContainerHighest: AppColors.surface,
    outline: AppColors.line,
    error: AppColors.danger,
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.night,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.night,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.text,
      titleTextStyle: AppText.title,
    ),
    textTheme: base.textTheme.copyWith(
      displaySmall: AppText.display,
      headlineMedium: AppText.headline,
      titleLarge: AppText.title,
      titleMedium: AppText.subtitle,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body.copyWith(fontSize: 14),
      labelLarge: AppText.button,
      labelMedium: AppText.label,
      bodySmall: AppText.caption,
    ),
    iconTheme: const IconThemeData(color: AppColors.text, size: 22),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 18),
      labelStyle: AppText.label,
      floatingLabelStyle: AppText.label.copyWith(color: AppColors.green),
      hintStyle: AppText.body.copyWith(color: AppColors.textFaint),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.green, 1.5),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.night : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.green : AppColors.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.green : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(AppColors.night),
      side: const BorderSide(color: AppColors.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.green,
      labelStyle: AppText.label.copyWith(color: AppColors.text),
      secondaryLabelStyle: AppText.label.copyWith(color: AppColors.night),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMuted,
      textColor: AppColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: Space.page),
      minVerticalPadding: Space.sm,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.night,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.textFaint, size: 24)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => AppText.caption.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.textFaint)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.line,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      titleTextStyle: AppText.title,
      contentTextStyle: AppText.body,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.green, textStyle: AppText.button.copyWith(fontSize: 15)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.green),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceRaised,
      contentTextStyle: AppText.bodyStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
  );
}
