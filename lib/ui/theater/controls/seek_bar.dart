import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../domain/models/skip_range.dart';

/// Custom, paintable seek/timeline bar — replaces media_kit's default seek bar
/// (which can't be painted on). Standard scrub/tap-to-seek + a played fill + a
/// thumb, PLUS the cached intro/outro skip regions shaded directly on the track
/// ([_SeekBarPainter] via [skipSpanFraction]).
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
    final scheme = Theme.of(context).colorScheme;
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
                trackColor: Colors.white24,
                playedColor: scheme.primary,
                thumbColor: scheme.primary,
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

  // Distinct marker hues, translucent so they tint the region over both the
  // played fill and the empty track: amber = intro (OP), green = outro (ED).
  static const _introColor = Color(0x99FFC107);
  static const _outroColor = Color(0x9966BB6A);

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 4.0;
    final cy = size.height / 2;
    final radius = Radius.circular(trackHeight / 2);
    final top = cy - trackHeight / 2;
    final bottom = cy + trackHeight / 2;

    // Background track.
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width, bottom, radius),
      Paint()..color = trackColor,
    );

    // Played fill.
    final playedX = (size.width * fraction).clamp(0.0, size.width);
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, playedX, bottom, radius),
      Paint()..color = playedColor,
    );

    // Skip-region markers, on the real timeline (replaces the old separate
    // strip). Positioned by skipSpanFraction against the file duration and
    // CLAMPED to [0,1] — an overhanging outro never draws past the bar. Drawn
    // over the fill so the region reads regardless of play progress; a missing
    // window draws nothing.
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

    shade(intro, _introColor);
    shade(outro, _outroColor);

    // Thumb.
    canvas.drawCircle(
      Offset(playedX, cy),
      scrubbing ? 8 : 6,
      Paint()..color = thumbColor,
    );
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
