import 'package:flutter/material.dart';

/// The blackout-dark Windows-XP design tokens — the SINGLE source of truth for
/// the visual identity. Every styled widget pulls colors, gradients, metrics,
/// and type from here (never a hand-picked literal), so retuning the look is a
/// change in one place. This is the design-system analogue of the app's
/// config-driven layout seams.
///
/// Aesthetic: XP's beveled, tactile, chunky chrome reimagined in a near-black
/// palette. Boldness is spent in ONE place — the glossy blue title bar (the
/// signature) — while every other surface stays blacked-out and beveled.
abstract final class Xp {
  // --- Palette ------------------------------------------------------------
  /// The void behind the window (desktop).
  static const Color desktop = Color(0xFF06070A);

  /// Window-frame / chrome base.
  static const Color frame = Color(0xFF14161B);

  /// Raised control / panel base (mid grey).
  static const Color surface = Color(0xFF181A20);
  static const Color surfaceAlt = Color(0xFF1E2128);

  /// Sunken content area — the inset "well" (grid background, text fields).
  static const Color well = Color(0xFF0B0C0F);

  /// Button face gradient (lit top → shaded bottom) and its hover brighten.
  static const Color controlTop = Color(0xFF353841);
  static const Color controlBot = Color(0xFF1D1F25);
  static const Color controlTopHover = Color(0xFF454D5E);
  static const Color controlBotHover = Color(0xFF262A34);

  // Bevel edges. Two rings per element: an outer (extreme) and inner (mild)
  // pair, like classic Windows 3D borders — bright on the lit (top-left) edges,
  // black on the shadowed (bottom-right) edges. Swap the direction for sunken.
  static const Color bevelHiSoft = Color(0xFF787E8B); // brightest lit (outer)
  static const Color bevelHi = Color(0xFF565C68); //     lit (inner)
  static const Color bevelLoSoft = Color(0xFF101218); // shadow (inner)
  static const Color bevelLo = Color(0xFF000000); //     darkest shadow (outer)

  static const Color divider = Color(0xFF2A2D35);

  // --- Text ---------------------------------------------------------------
  static const Color text = Color(0xFFE7E9EE);
  static const Color textDim = Color(0xFF969CA8);
  static const Color textFaint = Color(0xFF5C626E);
  static const Color textOnTitle = Color(0xFFFFFFFF);

  // --- Accent (XP "Luna" blue, luminous on black) -------------------------
  static const Color accent = Color(0xFF2F7DFF);
  static const Color accentBright = Color(0xFF5FA0FF);
  static const Color accentDeep = Color(0xFF0E2C6B);

  // --- Title bar / window frame (the signature) ---------------------------
  static const Color titleGloss = Color(0xFF6E9CEB); // 1px top highlight
  static const Color titleA = Color(0xFF2A63CC);
  static const Color titleB = Color(0xFF1B4AA8);
  static const Color titleC = Color(0xFF14409A);
  static const Color titleD = Color(0xFF0C2358);
  static const Color frameBlue = Color(0xFF1E4FAE); // active window border

  /// The glossy XP title-bar gradient: a brighter upper band, a hard sheen
  /// break near the middle, fading to a deep navy — the plastic "Luna" look.
  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [titleA, titleB, titleC, titleD],
    stops: [0.0, 0.45, 0.5, 1.0],
  );

  /// Raised control face gradient. [hover] brightens it (the cursor "warms"
  /// the plastic), preserving the top-lit → bottom-shaded direction.
  static LinearGradient controlGradient({bool hover = false}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: hover
        ? const [controlTopHover, controlBotHover]
        : const [controlTop, controlBot],
  );

  // --- Metrics ------------------------------------------------------------
  /// Width of a single bevel ring (a control has two = 2px of tactile edge).
  static const double bevel = 1;

  /// Rounded top corners of a window (bottom stays square, like XP).
  static const double windowRadius = 8;

  /// Blue active-window frame thickness — kept slim so the chunky chrome
  /// doesn't eat layout width.
  static const double frameWidth = 3;

  static const double titleBarHeight = 30;
  static const double scrollbarThickness = 16;

  /// Chunky control padding (icon/label buttons, toolbar items).
  static const EdgeInsets controlPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 7,
  );

  // --- Type ---------------------------------------------------------------
  /// XP-era UI face. Trebuchet MS shipped with XP and is its branding voice;
  /// the fallbacks degrade gracefully where it's absent.
  static const String fontFamily = 'Trebuchet MS';
  static const List<String> fontFallback = [
    'Verdana',
    'Tahoma',
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
  ];
}
