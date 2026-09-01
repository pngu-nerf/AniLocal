/// The bar's VFD **segmented level meter** — the ONE place its cell rendering
/// lives.
///
/// The seek timeline established this look (quantized cells, lit cyan with a
/// bloom behind the level, a brighter peak cell at the level itself, faint
/// unlit cells ahead), and it is the thing on the panel that reads most
/// convincingly as an instrument. The volume control now uses the SAME cells,
/// so "the meter look" is one definition rather than two that drift: change a
/// cell width or an alpha here and both meters move together.
///
/// The split is deliberate: this file owns PAINT and GEOMETRY only. Each meter
/// keeps its own gestures, because they are genuinely different — the seek bar
/// scrubs (a drag previews, the release commits the seek), while a level meter
/// sets live on every pointer sample. Sharing the paint is what stops the look
/// drifting; sharing the gestures would have forced one of those two behaviors
/// onto the other.
library;

import 'package:flutter/material.dart';

/// Geometry + levels of the segmented meter, straight from the seek bar it was
/// extracted from — the numbers ARE the look, so they live in one place.
abstract final class VfdMeter {
  /// One lit element and the dark gap after it.
  static const double cellWidth = 3;
  static const double cellGap = 1.5;
  static const double pitch = cellWidth + cellGap;

  /// Height of the lit cells (the meter is centred in whatever box it gets).
  static const double cellHeight = 8;

  /// Resting phosphor of an unlit cell — the same faint level the display uses
  /// everywhere for "etched but not lit".
  static const double unlitAlpha = 0.12;

  /// How many whole cells fit [width]. At least one, so a zero-width layout
  /// pass can't divide the meter out of existence.
  static int cellsAcross(double width) =>
      (width / pitch).floor().clamp(1, 100000);
}

/// Paint the meter's cells into [size], filling [fraction] of them.
///
/// [color] is the phosphor for both lit and unlit cells (unlit is the same hue
/// at [VfdMeter.unlitAlpha] — a dark etched cell, not a grey one). [peakColor]
/// is the brighter frontmost lit cell, which marks the level: the meter has no
/// separate playhead or thumb, the peak IS the position. [peakBloomAlpha] lets
/// a caller push the peak's halo up while the user is dragging.
///
/// The level SNAPS to whole cells so the meter always reads as quantized; any
/// precision (a seek target, a volume value) belongs to the caller, which keeps
/// its own continuous fraction and only draws through here.
void paintMeterCells(
  Canvas canvas,
  Size size, {
  required double fraction,
  required Color color,
  required Color peakColor,
  double peakBloomAlpha = 0.4,
}) {
  final cy = size.height / 2;
  final top = cy - VfdMeter.cellHeight / 2;
  final count = VfdMeter.cellsAcross(size.width);
  final unlit = Paint()..color = color.withValues(alpha: VfdMeter.unlitAlpha);
  final lit = Paint()..color = color;
  final peak = Paint()..color = peakColor;
  final bloom = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  final peakBloom = Paint()
    ..color = peakColor.withValues(alpha: peakBloomAlpha)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final litCount = (fraction.clamp(0.0, 1.0) * count).round().clamp(0, count);
  for (var i = 0; i < count; i++) {
    final rect = Rect.fromLTWH(
      i * VfdMeter.pitch,
      top,
      VfdMeter.cellWidth,
      VfdMeter.cellHeight,
    );
    final isLit = i < litCount;
    final isPeak = isLit && i == litCount - 1;
    if (isLit) canvas.drawRect(rect, isPeak ? peakBloom : bloom);
    canvas.drawRect(rect, isLit ? (isPeak ? peak : lit) : unlit);
  }
}

/// An INTERACTIVE segmented meter: the seek bar's cells, driven as a control.
///
/// Built for the volume level, which was the last stock Material widget on the
/// panel — a solid continuous slider among quantized lit cells, which is what
/// read as "app UI dropped on a display". Pointer position maps straight to a
/// fraction and reports live (tap anywhere, or drag across), the same
/// pointer→fraction mapping the seek bar uses; there is no thumb because the
/// peak cell is the level.
///
/// It paints, so it is invisible to screen readers and to `find.byType` on a
/// stock widget: [semanticLabel] + the percentage are published as a slider's
/// semantics, the same way `VfdReadout` labels its dot matrix.
class VfdLevelMeter extends StatelessWidget {
  const VfdLevelMeter({
    super.key,
    required this.fraction,
    required this.onChanged,
    required this.semanticLabel,
    this.color,
    this.peakColor,
    this.height = 24,
  });

  /// Current level, 0–1.
  final double fraction;

  /// Fires live on tap and on every drag sample — the same contract the
  /// [Slider] this replaced had, so the caller's behavior is unchanged.
  final ValueChanged<double> onChanged;

  /// Spoken name of the control ("Volume"); the value is added as a percentage.
  final String semanticLabel;

  final Color? color;
  final Color? peakColor;

  /// Box height. The cells are [VfdMeter.cellHeight] tall and centred in it, so
  /// this is really the tap target — kept generous, as the slider's was.
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lit = color ?? scheme.primary;
    final peak = peakColor ?? scheme.primary;
    return Semantics(
      slider: true,
      label: semanticLabel,
      value: '${(fraction.clamp(0.0, 1.0) * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          void set(double dx) => onChanged((dx / width).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => set(d.localPosition.dx),
            onHorizontalDragStart: (d) => set(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                painter: _LevelMeterPainter(
                  fraction: fraction,
                  color: lit,
                  peakColor: peak,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  _LevelMeterPainter({
    required this.fraction,
    required this.color,
    required this.peakColor,
  });

  final double fraction;
  final Color color;
  final Color peakColor;

  @override
  void paint(Canvas canvas, Size size) => paintMeterCells(
    canvas,
    size,
    fraction: fraction,
    color: color,
    peakColor: peakColor,
  );

  @override
  bool shouldRepaint(_LevelMeterPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.peakColor != peakColor;
}
