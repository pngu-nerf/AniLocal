import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../domain/models/skip_range.dart';
import '../../theme/xp_tokens.dart';

/// Custom, paintable seek/timeline bar — replaces media_kit's default seek bar
/// (which can't be painted on). Rendered as a VFD **segmented level meter**
/// (spectrum-analyzer cells: lit cyan up to the play position, unlit ahead),
/// the position quantized to the nearest cell (a brighter "peak" cell marks it —
/// no separate playhead line), PLUS the cached intro/outro skip regions shaded
/// in amber (the status color) directly on the track ([_SeekBarPainter] via
/// [skipSpanFraction]).
///
/// Self-contained: it reads position/duration from the [player] and seeks it;
/// it has no idea where in the bar it sits.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.player,
    this.introSkip,
    this.outroSkip,
  });

  final Player player;

  /// Cached OP/ED windows for the current episode (offline; from the AniSkip
  /// cache). A null window shades nothing — partial coverage is normal.
  final SkipRange? introSkip;
  final SkipRange? outroSkip;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragFraction; // non-null while scrubbing

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    widget.player.stream.position.listen((p) {
      if (mounted && _dragFraction == null) setState(() => _position = p);
    });
    widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _seekToFraction(double f) {
    final total = _duration.inMilliseconds;
    if (total <= 0) return;
    widget.player.seek(
      Duration(milliseconds: (f.clamp(0.0, 1.0) * total).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void update(double dx) =>
            setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekToFraction(d.localPosition.dx / width),
          onHorizontalDragStart: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          onHorizontalDragEnd: (_) {
            final f = _dragFraction;
            if (f != null) _seekToFraction(f);
            setState(() => _dragFraction = null);
          },
          child: SizedBox(
            height: 24,
            width: double.infinity,
            child: CustomPaint(
              painter: _SeekBarPainter(
                fraction: _fraction,
                trackColor: Xp.accent,
                playedColor: Xp.accent,
                thumbColor: Xp.accentBright,
                scrubbing: _dragFraction != null,
                // Markers are positioned against the ACTUAL file duration and
                // clamped by skipSpanFraction, so an outro window overhanging
                // the file end never draws past the bar.
                durationMs: _duration.inMilliseconds,
                intro: widget.introSkip,
                outro: widget.outroSkip,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter({
    required this.fraction,
    required this.trackColor,
    required this.playedColor,
    required this.thumbColor,
    required this.scrubbing,
    required this.durationMs,
    this.intro,
    this.outro,
  });

  final double fraction;
  final Color trackColor;
  final Color playedColor;
  final Color thumbColor;
  final bool scrubbing;
  final int durationMs;
  final SkipRange? intro;
  final SkipRange? outro;

  // Skip windows (OP/ED) are STATUS, so they shade in translucent amber — the
  // panel's reserved status color — over both lit and unlit cells. OP and ED
  // read apart by position (start vs end); one hue keeps the two-color rule.
  static const _skipColor = Color(0x80FFB43C);

  // Segmented-meter geometry (spectrum-analyzer cells).
  static const _cellWidth = 3.0;
  static const _cellGap = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const meterHeight = 8.0;
    final cy = size.height / 2;
    final top = cy - meterHeight / 2;
    final bottom = cy + meterHeight / 2;

    // Discrete cells: lit cyan (with bloom) up to the play position, faint
    // unlit cells ahead — the resting spectrum-analyzer look. The position
    // SNAPS to the nearest whole cell at ALL times (including mid-drag), so the
    // meter always reads as a quantized level — the frontmost lit cell is the
    // brighter "peak" that marks the position (no separate playhead line).
    // Seeking stays precise/continuous: the gesture handlers seek to the exact
    // fraction; only this DRAW is quantized.
    const pitch = _cellWidth + _cellGap;
    final count = (size.width / pitch).floor().clamp(1, 100000);
    final unlit = Paint()..color = trackColor.withValues(alpha: 0.12);
    final lit = Paint()..color = playedColor;
    final peak = Paint()..color = thumbColor;
    final bloom = Paint()
      ..color = playedColor.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final peakBloom = Paint()
      ..color = thumbColor.withValues(alpha: scrubbing ? 0.6 : 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final litCount = (fraction * count).round().clamp(0, count);
    for (var i = 0; i < count; i++) {
      final rect = Rect.fromLTWH(i * pitch, top, _cellWidth, meterHeight);
      final isLit = i < litCount;
      final isPeak = isLit && i == litCount - 1;
      if (isLit) canvas.drawRect(rect, isPeak ? peakBloom : bloom);
      canvas.drawRect(rect, isLit ? (isPeak ? peak : lit) : unlit);
    }

    // Skip-region markers, on the real timeline. Positioned by skipSpanFraction
    // against the file duration and CLAMPED to [0,1] — an overhanging outro
    // never draws past the bar. Drawn over the cells so the window reads
    // regardless of play progress; a missing window draws nothing.
    void shade(SkipRange? r, Color color) {
      final span = skipSpanFraction(r, durationMs);
      if (span == null) return;
      canvas.drawRect(
        Rect.fromLTRB(
          size.width * span.start,
          top,
          size.width * span.end,
          bottom,
        ),
        Paint()..color = color,
      );
    }

    shade(intro, _skipColor);
    shade(outro, _skipColor);
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.fraction != fraction ||
      old.scrubbing != scrubbing ||
      old.durationMs != durationMs ||
      old.intro != intro ||
      old.outro != outro;
}

/// Fractional `[start, end]` of a skip window across a [totalMs]-long episode,
/// CLAMPED to `[0, 1]` — so an outro window that overhangs the file end never
/// draws past the bar. Null when there's nothing to draw: no window, unknown
/// duration, or a degenerate span. Pure, so it's unit-testable. (Drives the
/// timeline markers painted on [SeekBar].)
({double start, double end})? skipSpanFraction(SkipRange? r, int totalMs) {
  if (r == null || totalMs <= 0) return null;
  final start = (r.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
  final end = (r.end.inMilliseconds / totalMs).clamp(0.0, 1.0);
  if (end <= start) return null;
  return (start: start, end: end);
}
