import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// The VFD "fine-instrument" [ThemeData], derived from [Xp] tokens and applied
/// app-wide.
///
/// The body face is [Xp.fontFamily] — set by the ONE switch in `xp_tokens.dart`,
/// which `Xp.chrome()` reads too, so the theme and the labels can never
/// disagree. A missing glyph still degrades through [Xp.fontFallback]. The
/// display role is the separate dot-matrix painter and never a font here.
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

    final t = base.textTheme;
    return base.copyWith(
      // The BODY type role, now carrying the CHROME treatment: thin (w300) +
      // letter-spaced, matte cream — so running text reads like the same
      // screen-printed labeling, not a separate weight. Sizes stay at the M3
      // metrics (copyWith preserves each role's height) so only weight/tracking/
      // color/family change — no layout shift. `.apply` then stamps the matte
      // body color + the active family onto EVERY role (dialogs, list tiles,
      // buttons included), so body text everywhere inherits it by construction.
      textTheme: t
          .copyWith(
            titleMedium: t.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
            bodyMedium: t.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.8,
            ),
            bodySmall: t.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.8,
            ),
          )
          .apply(
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
        textStyle: TextStyle(
          color: Xp.text,
          fontFamily: Xp.fontFamily,
          fontFamilyFallback: Xp.fontFallback,
          fontSize: 12,
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Xp.surface),
      snackBarTheme: SnackBarThemeData(
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
