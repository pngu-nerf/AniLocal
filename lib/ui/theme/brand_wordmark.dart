import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// The **AniLocal brand wordmark** — the app's name as a molded chrome-plastic
/// logo on the chassis, the way `Technics` is molded into the reference unit's
/// face plate. It is a PHYSICAL mark, not a lit one.
///
/// This is the fourth type role, and it exists precisely so branding can't be
/// confused with content:
/// - **DISPLAY** ([VfdReadout]) — lit cyan dot-matrix, only inside the black
///   screen. The brand is deliberately NOT this any more: a wordmark that glows
///   reads as a *readout* (something the machine is telling you), and it stole
///   screen width from the actual context line.
/// - **CHROME** ([ChromeLabel]) — thin tracked-out caps, silk-screened UI
///   labels. Close, but a wordmark needs more weight and a molded edge than a
///   button legend.
/// - **BRAND** (this) — an elegant roman SERIF ([Xp.brandFontFamily]) in
///   cream/chrome, matte, with a 1px molded lip: a dark shadow below and a
///   light highlight above the glyphs, plus a top-to-bottom chrome ramp across
///   their faces, so it reads as raised plastic catching room light. Never
///   glows, never sits on the black screen.
///
/// The serif is load-bearing, not decoration: it is the ONLY serif in the app,
/// so the maker's mark can't be mistaken for a UI label. Everything else on the
/// instrument is technical sans or dot-matrix.
///
/// Decorative only — the header wraps it in an `IgnorePointer` so the chassis
/// beneath stays draggable.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.fontSize = 16,
    this.abbreviated = false,
  });

  /// Cap size of the mark. The molded lip is a fixed 1px regardless, so the
  /// logo keeps the same physical relief at any size. A touch larger than the
  /// sans labels around it: the serif's smaller x-height would otherwise read
  /// as the smallest thing on the chassis.
  final double fontSize;

  /// Abbreviate to [shortText]. Driven by the SAME window-width signal that
  /// collapses the header tabs to icons (`XpTitleBar.showsLabels`), so the whole
  /// header contracts as one piece rather than in stages.
  final bool abbreviated;

  /// The mark itself — brand casing, never uppercased (unlike [ChromeLabel]).
  static const String text = 'AniLocal';

  /// The contracted mark for a narrow window — the initials, still serif and
  /// still molded, so it reads as the same badge rather than a different one.
  static const String shortText = 'AL';

  /// Top-to-bottom chrome ramp across the glyph faces: bright cream catching
  /// light at the top, the body cream through the middle, a shaded roll-off
  /// near the base, easing back up so the bottom edge doesn't read as dirt.
  static const LinearGradient _chrome = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Xp.wordmarkHi, Xp.wordmark, Xp.wordmarkLo, Xp.wordmark],
    stops: [0.0, 0.42, 0.76, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return Text(
      abbreviated ? shortText : text,
      maxLines: 1,
      style: TextStyle(
        fontFamily: Xp.brandFontFamily,
        fontFamilyFallback: Xp.brandFontFallback,
        fontSize: fontSize,
        // Regular weight with a little air: a roman serif carries its own
        // contrast, so bolding it would coarsen the logotype rather than
        // strengthen it. The tracking is engraved-nameplate, not tracked-out
        // legend (that's the CHROME role's trait, deliberately not shared).
        fontWeight: FontWeight.w400,
        letterSpacing: 0.9,
        height: 1,
        // Shadows paint BEHIND the glyphs, so an offset pair peeking out top
        // and bottom is the molded lip: lit edge above, cast shadow below.
        shadows: [
          Shadow(
            color: Xp.bevelLo.withValues(alpha: 0.9),
            offset: const Offset(0, 1),
            blurRadius: 1.2,
          ),
          Shadow(
            color: Xp.bevelHiSoft.withValues(alpha: 0.65),
            offset: const Offset(0, -1),
          ),
        ],
        // A shader instead of a flat color — the ramp is what makes it read as
        // molded rather than printed. The rect only needs the glyph HEIGHT (the
        // ramp is vertical), so the width is irrelevant.
        foreground: Paint()
          ..shader = _chrome.createShader(
            Rect.fromLTWH(0, 0, 1, fontSize * 1.15),
          ),
      ),
    );
  }
}
