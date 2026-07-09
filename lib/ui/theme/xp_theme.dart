import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// The blackout-XP [ThemeData], derived entirely from [Xp] tokens. Applied
/// (this pass) by wrapping ONLY the landing-page subtree in a `Theme`, so the
/// signature XP widgets carry the look and any plain Material widgets nearby
/// (text, snackbars, the settings dialog, text selection) adopt the same dark
/// palette and Trebuchet type — while every other screen keeps the current
/// theme until we style it in a later pass.
abstract final class XpTheme {
  static ThemeData data() {
    const scheme = ColorScheme.dark(
      primary: Xp.accent,
      onPrimary: Colors.white,
      secondary: Xp.accentBright,
      surface: Xp.surface,
      onSurface: Xp.text,
      error: Color(0xFFE36A5B),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: Xp.fontFamily,
      fontFamilyFallback: Xp.fontFallback,
      scaffoldBackgroundColor: Xp.desktop,
      dividerColor: Xp.divider,
      canvasColor: Xp.surface,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Xp.text,
        displayColor: Xp.text,
        fontFamily: Xp.fontFamily,
        fontFamilyFallback: Xp.fontFallback,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Xp.accentBright,
        selectionColor: Xp.accentDeep,
        selectionHandleColor: Xp.accent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Xp.accentBright,
        linearTrackColor: Xp.well,
      ),
      iconTheme: const IconThemeData(color: Xp.text),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: Xp.frame),
        textStyle: const TextStyle(
          color: Xp.text,
          fontFamily: Xp.fontFamily,
          fontFamilyFallback: Xp.fontFallback,
          fontSize: 12,
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Xp.surface),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Xp.surfaceAlt,
        contentTextStyle: TextStyle(
          color: Xp.text,
          fontFamily: Xp.fontFamily,
          fontFamilyFallback: Xp.fontFallback,
        ),
      ),
    );
  }
}
