import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../ui/glass.dart';
import 'brand_tokens.dart';
import 'cray_glass.dart';
import 'fonts.dart';

/// Every page paints its own mesh, underneath its (transparent) scaffold.
///
/// Wrapping each route rather than the whole app matters: with a single mesh
/// behind the Navigator, two transparent pages would show through each other
/// for the length of every transition.
class _MeshPageTransitions extends PageTransitionsBuilder {
  const _MeshPageTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      inner.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        MeshBackground(child: child),
      );
}

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
    // FilledButton.tonal reads these: the soft brand container, as the
    // design's secondary actions (Book now, Add money) - computed, not chosen.
    secondaryContainer: t.primaryContainer,
    onSecondaryContainer: t.onPrimaryContainer,
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

  final bodyFamily = fontFamilyFor(t.bodyFamily);
  final headingFamily = fontFamilyFor(t.headingFamily);
  final fallback = devanagariFallback;

  TextStyle body(double size, {int? weight}) => TextStyle(
        fontFamily: bodyFamily,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: bodyHeight,
        letterSpacing: letterSpacing,
        fontWeight: _weight(weight ?? t.bodyWeight),
        color: t.textPrimary,
      );

  TextStyle heading(double size) => TextStyle(
        fontFamily: headingFamily,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: t.isDevanagari ? 1.3 + (t.lineHeightBonus / 16) : 1.25,
        letterSpacing: letterSpacing,
        fontWeight: _weight(t.headingWeight),
        color: t.textPrimary,
      );

  final glass = CrayGlass.fromTokens(t);
  final sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    extensions: [glass],
    // Transparent: the mesh is painted per page, beneath (see above).
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _MeshPageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.iOS: _MeshPageTransitions(CupertinoPageTransitionsBuilder()),
        TargetPlatform.linux: _MeshPageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.macOS: _MeshPageTransitions(CupertinoPageTransitionsBuilder()),
        TargetPlatform.windows: _MeshPageTransitions(ZoomPageTransitionsBuilder()),
      },
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.glassSheet,
      modalBackgroundColor: t.glassSheet,
      surfaceTintColor: Colors.transparent,
      shape: sheetShape,
      showDragHandle: true,
      dragHandleColor: t.borderStrong,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.glassBar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.primaryContainer,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? t.onPrimaryContainer : t.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => body(13, weight: states.contains(WidgetState.selected) ? 600 : 400).copyWith(
          color: states.contains(WidgetState.selected) ? t.textPrimary : t.textSecondary,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.primaryContainer,
      foregroundColor: t.onPrimaryContainer,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 1,
      extendedTextStyle: body(15, weight: 600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        side: BorderSide(color: t.glassLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.glassSheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSheet)),
    ),
    dividerColor: t.divider,
    fontFamily: bodyFamily,
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
      // Over the mesh, and frosted once content scrolls under it.
      backgroundColor: Colors.transparent,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
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
      fillColor: t.glassCard,
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
    // Every Card in the app becomes a glass card: translucent over the mesh,
    // with the bright hairline. No blur here - see GlassPanel.
    cardTheme: CardThemeData(
      color: t.glassCard,
      surfaceTintColor: Colors.transparent,
      shadowColor: t.glassShadow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusBase),
        side: BorderSide(color: t.glassLine),
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
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusChip),
        side: BorderSide(color: t.borderStrong),
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
