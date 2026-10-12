import 'package:flutter/material.dart';
import 'button_styles.dart';

abstract final class AppColors {
  static const ink = Color(0xFF422D34);
  static const pink = Color(0xFFE71883);
  static const blush = Color(0xFFFFF0F6);
  static const softPink = blush;
  static const muted = Color(0xFF8A727D);
  static const line = Color(0xFFF0E7EC);
  static const background = Colors.white;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito',
    fontFamilyFallback: const ['NotoSansSymbols2'],
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.pink,
      primary: AppColors.pink,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FlowertoiButtonStyles.primary(),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: FlowertoiButtonStyles.secondary(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFAF7F9),
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.pink, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.blush,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: states.contains(WidgetState.selected)
              ? AppColors.pink
              : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? AppColors.pink
              : AppColors.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}
