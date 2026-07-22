import 'package:flutter/material.dart';

import 'vfd_readout.dart';
import 'xp_tokens.dart';

/// The header status readout — a little TRUE-BLACK "screen" set into the header
/// chassis. Inside it: an amber REMOTE-badge-style box around the fixed
/// `AniLocal` prefix + a cyan dot-matrix status/title. Idle on the library:
/// "AniLocal LIBRARY"; viewing a show: "AniLocal <TITLE>".
///
/// The screen is a **FIXED width** (roughly "ANILOCAL SAKAMOTO DAYS") — it does
/// NOT grow/shrink with the title or the window. Short titles sit static in the
/// title region; long titles scroll (marquee) within it, clipped to the box so
/// text appears/disappears cleanly at the edges. Content is STATIC per screen:
/// it changes only on a deliberate context change (navigating to a show), never
/// on hover.
///
/// Two-color palette: the "AniLocal" badge is AMBER (the status-accent color),
/// visually separating the fixed label from the changing CYAN title. True black
/// ([Xp.well]) makes the phosphor read as a lit display against the chassis.
class HeaderReadout extends StatelessWidget {
  const HeaderReadout({super.key, required this.title});

  /// The context word/title after the fixed "AniLocal" badge (dot-matrix caps):
  /// "Library" on the home library, or the show title.
  final String title;

  static const double _pitch = 2; // glyph height = 7 * pitch = 14
  static const double _gap = 8; // between the amber badge and the title
  // Fixed title-region width — holds ~"SAKAMOTO DAYS"; longer titles scroll.
  static const double _titleRegionW = 155;
  static const double _screenPadH = 6;
  static const double _screenPadV = 3;

  @override
  Widget build(BuildContext context) {
    const glyphH = 7 * _pitch;
    final titleW = VfdReadout.widthFor(title, dotPitch: _pitch);
    final overflow = titleW > _titleRegionW + 0.5;

    return DecoratedBox(
      // TRUE BLACK screen with a subtle machined bezel. Fixed width: the row
      // below is all fixed-size children, so the screen never grows/shrinks.
      decoration: BoxDecoration(
        color: Xp.well,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Xp.bevelLoSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _screenPadH,
          vertical: _screenPadV,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The fixed "REMOTE"-style badge — a thin amber outline (no glow),
            // rounded, snug around the CYAN dot-matrix "AniLocal".
            const _AmberBadge(),
            const SizedBox(width: _gap),
            // Fixed-width title region — the "window" the CYAN title lives in,
            // clipped so it appears/disappears cleanly at the edges.
            SizedBox(
              width: _titleRegionW,
              height: glyphH,
              child: ClipRect(
                child: overflow
                    ? _Marquee(title: title, textWidth: titleW, pitch: _pitch)
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: VfdReadout(title, dotPitch: _pitch),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The amber "REMOTE"-style badge around the fixed "AniLocal" label: JUST a thin
/// amber outline (rounded). No fill and NO glow — a boxShadow would bleed amber
/// through the transparent interior. The label inside is CYAN dot-matrix, the
/// same phosphor color as the title; the amber is only the outline.
class _AmberBadge extends StatelessWidget {
  const _AmberBadge();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(3)),
      border: Border.fromBorderSide(BorderSide(color: Xp.warning)),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: VfdReadout(
        'AniLocal',
        dotPitch: 2,
      ), // cyan (default) — matches title
    ),
  );
}

/// Scrolls [title] horizontally within its (clipped) parent when it's too wide
/// to fit. Two copies + a gap make the loop read as a seamless conveyor; a brief
/// pause sits at the top of each cycle with the title left-aligned and readable.
class _Marquee extends StatefulWidget {
  const _Marquee({
    required this.title,
    required this.textWidth,
    required this.pitch,
  });

  final String title;
  final double textWidth;
  final double pitch;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  // --- Scroll behavior (tune here; easy to swap to scroll-once) -------------
  static const double _pxPerSecond = 32; // slow + readable, not a fast crawl
  static const double _loopGap = 48; // blank run before the title repeats
  static const Duration _startPause = Duration(milliseconds: 900);

  late final AnimationController _controller;
  late final double _travel; // one full cycle's distance

  @override
  void initState() {
    super.initState();
    _travel = widget.textWidth + _loopGap;
    final scrollMs = (_travel / _pxPerSecond * 1000).round();
    _controller = AnimationController(
      vsync: this,
      duration: _startPause + Duration(milliseconds: scrollMs),
    );
    // Continuous loop. To switch to scroll-once-then-settle, replace `.repeat()`
    // with `.forward()` (it ends with the title back at the start).
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VfdReadout(widget.title, dotPitch: widget.pitch),
        const SizedBox(width: _loopGap),
        VfdReadout(widget.title, dotPitch: widget.pitch),
      ],
    );
    final pauseFraction =
        _startPause.inMilliseconds / _controller.duration!.inMilliseconds;

    // OverflowBox lets the (too-wide) content lay out at its natural width; the
    // parent ClipRect masks it to the black screen's title region.
    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final progress = t <= pauseFraction
              ? 0.0
              : (t - pauseFraction) / (1 - pauseFraction);
          return Transform.translate(
            offset: Offset(-progress * _travel, 0),
            child: child,
          );
        },
        child: content,
      ),
    );
  }
}
