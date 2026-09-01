/// The player bar's DISPLAY-role controls — the one place the bar's look is
/// defined.
///
/// The bar sits ON a lit panel now (a true-black VFD screen, the header
/// readout's surface run edge-to-edge), so its controls are *screen* elements,
/// not chassis ones: phosphor glyphs and dot-matrix legends that glow, never
/// molded keys with bevels and gradients. That is the whole point of this file
/// — before it, each control styled itself (Material bone-white [IconButton]s,
/// chassis [XpButton]s, a stock [Slider], one dot-matrix readout), which is
/// what read as piecemeal.
///
/// It does NOT replace [XpButton]: that is the CHASSIS role (a physical key on
/// the machine's face — header, dialogs, cards) and stays exactly as it is.
/// This is its display-role counterpart, and the two never mix on one surface.
/// Every control on the bar goes through the widgets here, so re-tuning the
/// bar's look is an edit in this file and nowhere else.
///
/// Behavior is deliberately unchanged: each widget wraps the SAME interactive
/// primitive the control used before ([IconButton], [Slider]) with the same
/// tooltip and the same callback, so hit-testing, tooltips and the player's
/// focus rules are untouched by the restyle.
library;

import 'package:flutter/material.dart';

import '../../theme/header_readout.dart';
import '../../theme/vfd_readout.dart';
import '../../theme/xp_tokens.dart';
import 'segmented_meter.dart';

/// Phosphor levels for the panel. Lit = an armed/active legend; rest = a
/// control at idle, still clearly lit (this is a display, not a dimmed toolbar);
/// dead = disabled.
const Color _lit = Xp.accentBright;
const Color _rest = Xp.accent;
const Color _dead = Xp.textFaint;

/// A legend that is etched but NOT lit — the display's "off" state.
///
/// Deliberately the same level the segmented meter uses for an unlit cell
/// ([VfdMeter.unlitAlpha]), because it is the same idea: the element is
/// physically there, it just isn't energised. Sharing the number is what makes
/// a dark play glyph and a dark meter cell read as the same display.
const double _ghostAlpha = VfdMeter.unlitAlpha;

/// The dot pitch EVERY readout on the bar uses — time, EP, button legends.
///
/// ONE constant, so the panel has one type size and it can't drift between
/// them. It is 2 because a glyph is 7 dots tall: 14pt, which is what the
/// Material glyphs beside it actually DRAW inside their 20pt boxes (those
/// shapes fill roughly 12–15pt of the box). At pitch 3 the text stood 21pt and
/// towered over the icons it shares a row with. It is also the header
/// readout's pitch ([HeaderReadout.pitch]), so a line of text on a screen is
/// one size everywhere in the app.
const double kVfdBarPitch = 2;

/// A phosphor glyph with its bloom — the icon half of every display control.
///
/// The halo is proportional to the icon and drawn by the glyph itself
/// ([Icon.shadows]) rather than a container shadow, so it lights the strokes and
/// not a box around them — the same "lit dot, not a fuzzy blob" rule
/// [VfdReadout] follows for its dots.
class VfdGlyph extends StatelessWidget {
  const VfdGlyph(this.icon, {super.key, this.size = 20, this.color = _rest});

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    size: size,
    color: color,
    shadows: [
      Shadow(color: color.withValues(alpha: 0.55), blurRadius: size * 0.35),
    ],
  );
}

/// A bar icon control (play/pause, mute, subtitles, settings, ⛶, cancel).
///
/// Still an [IconButton] underneath — same 48pt tap target, same tooltip, same
/// `onPressed` — so nothing about hit-testing or the tooltip-dismiss guard
/// changes. Only the paint differs: a phosphor glyph, and hover/press feedback
/// as a faint accent wash instead of Material's grey ink, which on a black
/// display reads as smudge.
class VfdIconButton extends StatefulWidget {
  const VfdIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.ghost,
    this.lit = false,
    this.size = 20,
  });

  /// The LIT legend — for a state pair (see [ghost]) this is the state the
  /// player is in, not the action the tap performs.
  final IconData icon;

  /// Names the ACTION, always — a state pair lights what is true, but pressing
  /// it still does the other thing, and the tooltip is where that is said.
  final String tooltip;

  final VoidCallback? onPressed;

  /// The dark twin, drawn beside [icon] at [_ghostAlpha].
  ///
  /// This is the state language a display has and a toolbar doesn't: a deck
  /// etches both ▶ and ‖ and lights the one that is true, instead of swapping a
  /// single glyph. Only controls with a real either/or pass it; a control whose
  /// state is elsewhere (the volume meter's cells, the ⛶ mode) doesn't invent
  /// a twin. Purely visual — the tap and the tooltip are unaffected.
  final IconData? ghost;

  /// Brightest phosphor — for a control that is currently doing something.
  final bool lit;

  final double size;

  @override
  State<VfdIconButton> createState() => _VfdIconButtonState();
}

class _VfdIconButtonState extends State<VfdIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? _dead
        : (widget.lit || _hover)
        ? _lit
        : _rest;
    final glyph = VfdGlyph(widget.icon, size: widget.size, color: color);
    return MouseRegion(
      // Hover BRIGHTENS the phosphor instead of washing a grey Material
      // rectangle over it — a lit element responds by getting brighter, and on
      // true black the ink overlay reads as a smudge. Cursor is left to defer:
      // the IconButton inside still sets the click cursor, and the overlay's
      // cursor-hide (which owns the video area) must stay in charge.
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        style: IconButton.styleFrom(
          foregroundColor: color,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        icon: widget.ghost == null
            ? glyph
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  glyph,
                  const SizedBox(width: 3),
                  VfdGlyph(
                    widget.ghost!,
                    size: widget.size,
                    color: color.withValues(alpha: _ghostAlpha),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A bar action control with a legend — Skip Intro / Skip Outro / Play next.
///
/// The display-role answer to [XpButton]: no molded face, no bevel; a hairline
/// segment frame around a lit dot-matrix legend, so the transient affordances
/// read as part of the same display as the timer beside them. The legend is a
/// [VfdReadout], i.e. literally the same typeface as the rest of the panel.
///
/// [VfdReadout]'s glyph table covers A–Z, digits and a few marks, so a legend
/// must stay within that set (it uppercases for you); anything else renders
/// blank. Detail that doesn't fit the legend belongs in [tooltip], which is
/// ordinary text.
class VfdActionButton extends StatefulWidget {
  const VfdActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.lit = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// ARMED — the affordance is live right now (inside a skip window, or the
  /// pre-roll counting down). Lights the frame and the legend.
  final bool lit;

  @override
  State<VfdActionButton> createState() => _VfdActionButtonState();
}

class _VfdActionButtonState extends State<VfdActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? _dead
        : (widget.lit || _hover)
        ? _lit
        : _rest;
    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        // The segment's own faint backlight, brighter while armed — the frame
        // and fill are the only non-glyph paint on the panel.
        color: enabled
            ? Xp.accent.withValues(alpha: widget.lit ? 0.14 : 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: color.withValues(alpha: enabled ? 0.55 : 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VfdGlyph(widget.icon, size: 14, color: color),
            const SizedBox(width: 7),
            VfdReadout(widget.label, dotPitch: kVfdBarPitch, color: color),
          ],
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onPressed, child: button),
    );
  }
}
