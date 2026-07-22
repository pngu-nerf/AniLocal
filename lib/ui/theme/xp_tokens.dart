import 'package:flutter/material.dart';

/// VFD "fine-instrument" design tokens — the SINGLE source of truth for the
/// visual identity, modelled on the **Technics SC-CH900 (1992)** display panel.
/// Every styled widget pulls colors, metrics, and type from here (never a
/// hand-picked literal), so retuning the look is a change in one place.
///
/// The class + member names are kept from the app's earlier "blackout-XP"
/// identity so this is a pure *styling* swap — the composable architecture and
/// all consumers are untouched. Read the names as roles, not literal XP parts
/// (`titleGradient` = the chassis header fill, `bevel*` = the instrument's
/// metal bezel, `accent` = the cyan phosphor, etc.).
///
/// Aesthetic rules baked into these values:
/// - **Two phosphor colors on true black:** cyan-white primary ([accent]),
///   amber secondary ([warning], reserved for status). NO third accent hue.
/// - **NO gradients** — every "gradient" token is a flat two-stop of one color.
///   Depth comes from thin, restrained metal bezels, not glossy fills.
/// - **Sparse-lit against dark:** most surfaces are black or dark brushed
///   metal; glow (the dot-matrix readouts' bloom) is spent only on lit
///   elements, never decoratively.
/// - **Cream wordmark** ([wordmark]) for branding labels; calm cyan-tinted
///   off-white ([text]) for legible body/list text (NOT glowing).
abstract final class Xp {
  // --- Grounds -------------------------------------------------------------
  /// True black — the void behind the window and the phosphor display field.
  static const Color desktop = Color(0xFF000000);

  /// Sunken content area (the "well" / display field where phosphor sits) —
  /// true black so lit elements read as glowing against it.
  static const Color well = Color(0xFF000000);

  // --- Chassis (dark brushed metal) ---------------------------------------
  /// Window-frame / chrome base — the instrument chassis.
  static const Color frame = Color(0xFF16181C);

  /// Raised control / panel face (brushed-metal grey).
  static const Color surface = Color(0xFF191C21);
  static const Color surfaceAlt = Color(0xFF20242A);

  /// Chassis button faces. NO gradient — [controlGradient] returns a flat fill;
  /// [hover] lifts it a touch (the metal "warms" under the cursor).
  static const Color controlTop = Color(0xFF23272D);
  static const Color controlBot = Color(0xFF23272D);
  static const Color controlTopHover = Color(0xFF2C313A);
  static const Color controlBotHover = Color(0xFF2C313A);

  // Bezel edges — a subtle single metal highlight (top-left) + shadow
  // (bottom-right), NOT the chunky bright/black XP bevel. Two rings still exist
  // in the primitive, but the colors are restrained so the edge reads as a
  // fine machined lip, not a toy 3D border.
  static const Color bevelHiSoft = Color(0xFF3A3F46); // metal highlight (outer)
  static const Color bevelHi = Color(0xFF2A2E34); //     highlight (inner)
  static const Color bevelLoSoft = Color(0xFF0A0B0D); // shadow (inner)
  static const Color bevelLo = Color(0xFF000000); //     shadow (outer)

  static const Color divider = Color(0xFF23262B);

  // --- Text (BODY role) ----------------------------------------------------
  /// Body/list text: a matte warm off-white, as if silk-screened onto the dark
  /// chassis. Deliberately NOT cyan and NOT glowing — the lit cyan phosphor is
  /// reserved for the display role (VfdReadout), so body reads as PRINTED and
  /// the readouts as LIT. That printed-vs-lit split is the core of the look.
  static const Color text = Color(0xFFE0DCD1);
  static const Color textDim = Color(0xFF9C978B);
  static const Color textFaint = Color(0xFF625D53);

  /// Cream wordmark for branding labels (the chassis header caption). Warm, to
  /// read as a silk-screened logo against the metal.
  static const Color wordmark = Color(0xFFECE4D0);
  static const Color textOnTitle = wordmark;

  // --- Phosphor accents ----------------------------------------------------
  /// Primary phosphor — lit readouts, active/selected elements. A MILKY,
  /// low-chroma grey-cyan, as if seen through a tinted/smoked screen: hue held
  /// in the cyan/teal region (~186°) but saturation pulled way down and a little
  /// of the black ground mixed in, so it reads hazy/behind-glass rather than a
  /// clean vivid glow. (Was 0xFF4FE3F5, HSV S≈68% — now S≈28%.) Changing this
  /// one token re-treats every display-role element at once (VfdReadout's
  /// default, the seek meter, caption glows).
  static const Color accent = Color(0xFF93C6CC);
  static const Color accentBright = Color(0xFFA6F2FF);

  /// Dim cyan — text-selection fill, faint-lit segments, inactive phosphor.
  static const Color accentDeep = Color(0xFF0C3A44);

  /// Amber secondary phosphor — RESERVED for status / accent (the "REMOTE"
  /// badge role): the "+X" extra-episodes hint, attention states, warnings.
  /// Never used decoratively; its scarcity is what makes it read as status.
  static const Color warning = Color(0xFFFFB43C);

  // --- Chassis header (was the "title bar") --------------------------------
  /// Thin lit hairline under the top edge of the header — a single cyan rule.
  static const Color titleGloss = Color(0xFF2A5A63);
  static const Color titleA = Color(0xFF15171B);
  static const Color titleB = Color(0xFF121418);
  static const Color titleC = Color(0xFF101216);
  static const Color titleD = Color(0xFF0C0E11);

  /// Active-window frame — a dark machined metal edge (was XP blue).
  static const Color frameBlue = Color(0xFF2A2F36);

  /// The chassis header fill — flat dark brushed metal (NO gradient; the stops
  /// only vary by a hair so a machined top-to-bottom grain is barely sensed).
  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [titleA, titleB, titleC, titleD],
    stops: [0.0, 0.45, 0.5, 1.0],
  );

  /// Chassis control face — a FLAT fill (both stops equal). [hover] lifts it.
  static LinearGradient controlGradient({bool hover = false}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: hover
        ? const [controlTopHover, controlBotHover]
        : const [controlTop, controlBot],
  );

  // --- Metrics -------------------------------------------------------------
  /// Width of a single bezel ring (an element has two = a 2px machined lip).
  static const double bevel = 1;

  /// Window corner radius — nearly square; a fine instrument, not a soft card.
  static const double windowRadius = 4;

  /// Chassis frame thickness — slim, so the metal edge doesn't eat layout.
  static const double frameWidth = 2;

  static const double titleBarHeight = 30;
  static const double scrollbarThickness = 16;

  /// Chunky control padding (icon/label buttons, toolbar items).
  static const EdgeInsets controlPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 7,
  );

  // --- Type: three roles, mirroring the reference device -------------------
  // 1. DISPLAY  — lit dot-matrix readouts (time, counters, status; the header
  //    "AniLocal" branding screen — see `HeaderReadout`). Rendered by the
  //    `VfdReadout` painter, NOT a font. Glows cyan/amber against black.
  // 2. BODY     — running text / lists: the legible sans below ([fontFamily]),
  //    matte cream ([text]). Set once in the theme (see xp_theme.dart).
  // 3. CHROME   — thin, tracked-out, matte UPPERCASE labels "screen-printed on
  //    the chassis" (titles, section headers, button/tab labels). NOT glowing,
  //    NOT cyan — printed, part of the metal. See [chrome].

  /// Legible technical sans — the BODY voice (running text, lists).
  static const String fontFamily = 'Helvetica Neue';
  static const List<String> fontFallback = [
    'Helvetica',
    'Arial',
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
  ];

  /// The CHROME label style — the defining "labeled fine-equipment" look: a
  /// light weight + GENEROUS letter-spacing (the key trait) in matte cream/grey,
  /// no glow. Callers uppercase the text (see the `ChromeLabel` widget). A
  /// single source so every title/label/button reads as one screen-printed set.
  static TextStyle chrome({
    double fontSize = 12,
    Color color = text,
    FontWeight weight = FontWeight.w300,
    double letterSpacing = 2,
    double height = 1.1,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: fontSize,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );
}
