import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// A **segmented bar-graph meter** — the SC-CH900's spectrum-analyzer / level
/// look, reused everywhere the app shows linear progress (the player seek bar,
/// continue-watching progress). A row of discrete cells: cells up to [fraction]
/// are lit phosphor with a soft bloom; the rest are the resting unlit dark
/// cells. Flat colors, no gradient.
///
/// Purely presentational. For an interactive seek bar the gesture handling +
/// skip-region shading live in the player's own bar; this is the static
/// progress primitive and the shared visual vocabulary.
class VfdMeter extends StatelessWidget {
  const VfdMeter({
    super.key,
    required this.fraction,
    this.color = Xp.accent,
    this.height = 6,
    this.cellWidth = 3,
    this.cellGap = 1.5,
    this.glow = true,
  });

  /// Played / filled portion in `[0, 1]`.
  final double fraction;
  final Color color;
  final double height;

  /// Width and inter-cell gap of a single segment cell.
  final double cellWidth;
  final double cellGap;
  final bool glow;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: SegmentMeterPainter(
        fraction: fraction.clamp(0.0, 1.0),
        color: color,
        cellWidth: cellWidth,
        cellGap: cellGap,
        glow: glow,
      ),
    ),
  );
}

/// Paints a segmented meter across the whole [size]. Shared by [VfdMeter] and
/// the player seek bar (which layers gestures, skip regions, and a thumb on
/// top). Lit cells (≤ [fraction]) glow; the rest are unlit dark cells.
class SegmentMeterPainter extends CustomPainter {
  SegmentMeterPainter({
    required this.fraction,
    required this.color,
    this.cellWidth = 3,
    this.cellGap = 1.5,
    this.glow = true,
  });

  final double fraction;
  final Color color;
  final double cellWidth;
  final double cellGap;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = cellWidth + cellGap;
    final count = (size.width / pitch).floor().clamp(1, 100000);
    final litUntil = fraction * count;

    final unlit = Paint()..color = color.withValues(alpha: 0.10);
    final lit = Paint()..color = color;
    final bloom = glow
        ? (Paint()
            ..color = color.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5))
        : null;

    for (var i = 0; i < count; i++) {
      final x = i * pitch;
      final rect = Rect.fromLTWH(x, 0, cellWidth, size.height);
      final isLit = i < litUntil;
      if (isLit && bloom != null) canvas.drawRect(rect, bloom);
      canvas.drawRect(rect, isLit ? lit : unlit);
    }
  }

  @override
  bool shouldRepaint(SegmentMeterPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.cellWidth != cellWidth ||
      old.cellGap != cellGap ||
      old.glow != glow;
}
