import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// The BODY font, chosen here for a temporary side-by-side comparison. Flip the
/// active face by editing the ONE `_bodyFont` line below. Candidates are bundled
/// OFL assets (see the `fonts:` block in pubspec.yaml); [helveticaNeue] uses the
/// platform face in [Xp.fontFamily].
///
/// TEMPORARY scaffolding — once a winner is picked, this enum + switch collapse
/// to the single chosen font and the losing assets/pubspec entries are removed
/// (per the cleanup contract). The DISPLAY role (dot-matrix) is a painter
/// (`VfdReadout`) that uses NO font, so it is unaffected by this switch.
enum BodyFont { helveticaNeue, ibmPlexMono, spaceGrotesk, archivo }

/// ⇩⇩⇩  THE SWITCH — edit THIS ONE LINE to compare body faces.  ⇩⇩⇩
const BodyFont _bodyFont = BodyFont.helveticaNeue;

/// The active body font's family + fallback, resolved from [_bodyFont]. A
/// missing glyph still degrades through the sans fallback stack.
({String family, List<String> fallback})
_resolveBodyFont() => switch (_bodyFont) {
  BodyFont.helveticaNeue => (family: Xp.fontFamily, fallback: Xp.fontFallback),
  BodyFont.ibmPlexMono => (family: 'IBM Plex Mono', fallback: Xp.fontFallback),
  BodyFont.spaceGrotesk => (family: 'Space Grotesk', fallback: Xp.fontFallback),
  BodyFont.archivo => (family: 'Archivo', fallback: Xp.fontFallback),
};

/// The VFD "fine-instrument" [ThemeData], derived from [Xp] tokens and applied
/// app-wide. The body font comes from the [_bodyFont] switch (single source);
/// the display role is the separate dot-matrix painter and never a font here.
abstract final class XpTheme {
  static ThemeData data() {
    final body = _resolveBodyFont();
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
      fontFamily: body.family,
      fontFamilyFallback: body.fallback,
      scaffoldBackgroundColor: Xp.desktop,
      dividerColor: Xp.divider,
      canvasColor: Xp.surface,
    );

    final t = base.textTheme;
    return base.copyWith(
      // The BODY type role — the single source of running-text hierarchy (the
      // lit dot-matrix DISPLAY role is VfdReadout, entirely separate). A small
      // deliberate title / body / caption scale; sizes stay at the M3 metrics
      // (copyWith preserves each role's height + letter-spacing) so this only
      // sets weight/color/family — no layout shift. `.apply` then stamps the
      // matte body color + Helvetica Neue onto EVERY role, including the
      // Material-chrome roles used by dialogs, list tiles, and buttons, so body
      // text everywhere inherits the printed chassis treatment by construction.
      textTheme: t
          .copyWith(
            titleMedium: t.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            bodyMedium: t.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            bodySmall: t.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          )
          .apply(
            bodyColor: Xp.text,
            displayColor: Xp.text,
            fontFamily: body.family,
            fontFamilyFallback: body.fallback,
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
          fontFamily: body.family,
          fontFamilyFallback: body.fallback,
          fontSize: 12,
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Xp.surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Xp.surfaceAlt,
        contentTextStyle: TextStyle(
          color: Xp.text,
          fontFamily: body.family,
          fontFamilyFallback: body.fallback,
        ),
      ),
    );
  }
}
