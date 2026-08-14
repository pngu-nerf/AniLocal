import 'package:flutter/material.dart';

import 'vfd_readout.dart';
import 'xp_tokens.dart';

/// The header status readout — a little TRUE-BLACK "screen" set into the header
/// chassis, showing the app's CONTEXT in cyan dot-matrix: "LIBRARY" on the home
/// library, the show title on a detail page.
///
/// The screen shows the context ONLY. Branding is not a readout: "AniLocal" is
/// a molded chrome logo on the chassis beside the screen (`BrandWordmark`), so
/// the screen never repeats it and its whole width is spent on the one thing
/// that actually changes. Content is STATIC per screen — it changes only on a
/// deliberate context change (navigating to a show), never on hover.
///
/// **Width comes from the parent** (`XpTitleBar` sizes it so the screen is
/// centred on the window — see there), so this widget needs a BOUNDED width and
/// fills it. Fit is therefore recomputed live at every window size: a title
/// that fits when the window is wide starts scrolling when it narrows past its
/// fit point. Fits → centred and static; overflows → marquee. Either way the
/// text is clipped to the black screen, so it appears/disappears cleanly at the
/// edges and never spills onto the chrome.
class HeaderReadout extends StatelessWidget {
  const HeaderReadout({super.key, required this.title});

  /// The context word/title in the screen: "Library" on the home library, or
  /// the show title.
  final String title;

  static const double _pitch = 2; // glyph height = 7 * pitch = 14
  static const double _screenPadH = 6;
  static const double _screenPadV = 3;
  static const double _glyphH = 7 * _pitch;

  @override
  Widget build(BuildContext context) {
    // Fill the width the parent allotted, and decide fit against THAT — the
    // allotment shrinks as the window narrows, so the marquee kicks in exactly
    // when the title stops fitting.
    return _screen(
      child: SizedBox(
        height: _glyphH,
        child: LayoutBuilder(
          builder: (context, constraints) => _title(constraints.maxWidth),
        ),
      ),
    );
  }

  /// The physical screen: true black with a subtle machined bezel, its content
  /// inset from the edges.
  Widget _screen({required Widget child}) => DecoratedBox(
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
      child: child,
    ),
  );

  /// The lit title inside [regionW] of screen: centred when it fits, scrolling
  /// when it doesn't. Clipped either way.
  Widget _title(double regionW) {
    final textW = VfdReadout.widthFor(title, dotPitch: _pitch);
    final overflow = textW > regionW + 0.5;
    return ClipRect(
      child: overflow
          // Keyed by title so a context change rebuilds the marquee with the
          // new text's travel distance instead of reusing the old one's.
          ? _Marquee(
              key: ValueKey(title),
              title: title,
              textWidth: textW,
              pitch: _pitch,
            )
          : Align(child: VfdReadout(title, dotPitch: _pitch)),
    );
  }
}

/// Scrolls [title] horizontally within its (clipped) parent when it's too wide
/// to fit. Two copies + a gap make the loop read as a seamless conveyor; a brief
/// pause sits at the top of each cycle with the title left-aligned and readable.
class _Marquee extends StatefulWidget {
  const _Marquee({
    super.key,
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
