import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Builds Flutter's theme from the salon's resolved tokens.
///
/// Every colour here comes from [BrandTokens]. Nothing is tinted with the brand
/// beyond the roles that are allowed to carry it: surfaces stay neutral, status
/// colours stay fixed, and body text never sits on the brand colour
/// (`DESIGN.md` 3.3).
ThemeData brandTheme(BrandTokens t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.primaryContainer,
    onPrimaryContainer: t.onPrimaryContainer,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.danger,
    // The danger colour is fixed and dark enough for white in both modes.
    onError: const Color(0xFFFFFFFF),
    surface: t.surface,
    onSurface: t.textPrimary,
    surfaceContainerLowest: t.surfaceSunken,
    surfaceContainerHighest: t.surfaceAlt,
    onSurfaceVariant: t.textSecondary,
    outline: t.borderStrong,
    outlineVariant: t.border,
  );

  // Devanagari needs the extra leading; Latin must not get it, or the rhythm
  // of an English screen changes for no reason (`DESIGN.md` 5.3).
  final bodyHeight = t.isDevanagari ? 1.5 + (t.lineHeightBonus / 16) : 1.45;
  final letterSpacing = t.isDevanagari ? 0.0 : null;

  TextStyle body(double size, {int? weight}) => TextStyle(
        fontFamily: t.bodyFamily,
        fontSize: size,
        height: bodyHeight,
        letterSpacing: letterSpacing,
        fontWeight: _weight(weight ?? t.bodyWeight),
        color: t.textPrimary,
      );

  TextStyle heading(double size) => TextStyle(
        fontFamily: t.headingFamily,
        fontSize: size,
        height: t.isDevanagari ? 1.3 + (t.lineHeightBonus / 16) : 1.25,
        letterSpacing: letterSpacing,
        fontWeight: _weight(t.headingWeight),
        color: t.textPrimary,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.surface,
    dividerColor: t.divider,
    fontFamily: t.bodyFamily,
    textTheme: TextTheme(
      displaySmall: heading(32),
      headlineMedium: heading(26),
      headlineSmall: heading(22),
      titleLarge: heading(20),
      titleMedium: body(16, weight: 600),
      bodyLarge: body(16),
      bodyMedium: body(15),
      bodySmall: body(13).copyWith(color: t.textSecondary),
      labelLarge: body(15, weight: 600),
      labelMedium: body(13, weight: 600).copyWith(color: t.textSecondary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.surface,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: heading(20),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        // 48dp minimum touch target (`DESIGN.md` 4.4).
        minimumSize: const Size.fromHeight(48),
        textStyle: body(16, weight: 600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusBase),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.brandInk,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: t.border),
        textStyle: body(16, weight: 600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusBase),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.brandInk),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceAlt,
      hintStyle: body(16).copyWith(color: t.textMuted),
      labelStyle: body(15).copyWith(color: t.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        borderSide: BorderSide(color: t.brandInk, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        borderSide: BorderSide(color: t.danger),
      ),
    ),
    cardTheme: CardThemeData(
      color: t.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        side: BorderSide(color: t.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceAlt,
      side: BorderSide(color: t.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusChip),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.primary : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(t.onPrimary),
      side: BorderSide(color: t.borderStrong, width: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceSunken,
      contentTextStyle: body(15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusChip),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.brandInk),
  );
}

FontWeight _weight(int value) => switch (value) {
      <= 300 => FontWeight.w300,
      <= 400 => FontWeight.w400,
      <= 500 => FontWeight.w500,
      <= 600 => FontWeight.w600,
      <= 700 => FontWeight.w700,
      _ => FontWeight.w800,
    };
