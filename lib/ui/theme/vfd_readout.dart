import 'package:flutter/material.dart';

import 'xp_tokens.dart';

/// A **dot-matrix readout** — the SC-CH900's display voice, and the SINGLE
/// source of truth for the app's "display" type role. Anything that should read
/// as a lit panel readout goes through this ONE widget: the playback timer, the
/// section headers ("EPISODES", "CONTINUE WATCHING"), counters, episode
/// numbers. (The complementary "body" role — running text, lists — is the
/// legible sans in `Xp.fontFamily`; the two roles never mix mechanisms.)
///
/// This is deliberately NOT a font. It renders each character as a 5×7 grid of
/// round phosphor dots via a hand-authored glyph table + a [CustomPainter], so
/// there is nothing to register or scope — a widget is available app-wide by
/// construction (a font asset would have to be declared in pubspec and could go
/// missing / fall back; this can't). Offline-safe, license-clean, dependency-
/// free. Sizes itself to its text and carries a [Semantics] label so it is
/// accessible to screen readers and findable in tests.
///
/// The defaults ARE the canonical display look (cyan phosphor, [dotPitch] 3,
/// bloom on, no resting grid) — call sites pass only the text, so the role
/// can't drift per-component. [dotPitch] varies the size like a font-size while
/// keeping the identical typeface (drop it for a compact inline counter).
class VfdReadout extends StatelessWidget {
  const VfdReadout(
    this.text, {
    super.key,
    this.color = Xp.accent,
    this.dotPitch = 3,
    this.glow = true,
    this.showGrid = false,
  });

  final String text;

  /// Phosphor color of lit dots (cyan by default; amber for status readouts).
  final Color color;

  /// Center-to-center spacing of dots, in logical px. Glyph height = 7·pitch.
  final double dotPitch;

  /// Soft phosphor bloom on lit dots. Off for tiny/dense readouts.
  final bool glow;

  /// Draw the unlit dot grid faintly (the resting phosphor of a real display).
  final bool showGrid;

  /// Rendered width for [text] at [dotPitch] WITHOUT building the widget — lets
  /// a parent (e.g. the header marquee) measure and lay out around a readout.
  /// Each glyph is 5 dots wide with a 1-dot gap between glyphs.
  static double widthFor(String text, {double dotPitch = 3}) {
    final n = text.length;
    if (n == 0) return 0;
    return (n * 5 + (n - 1)) * dotPitch;
  }

  /// Rendered pixel size of the readout for the given [text] and [dotPitch].
  Size get _size => Size(widthFor(text, dotPitch: dotPitch), 7 * dotPitch);

  @override
  Widget build(BuildContext context) {
    final s = _size;
    // Semantics label so the readout is spoken by screen readers and findable
    // in tests (a CustomPainter draws no Text, so it would otherwise be
    // invisible to both).
    return Semantics(
      label: text,
      child: SizedBox(
        width: s.width,
        height: s.height,
        child: CustomPaint(
          painter: _DotMatrixPainter(
            text: text.toUpperCase(),
            color: color,
            dotPitch: dotPitch,
            glow: glow,
            showGrid: showGrid,
          ),
        ),
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  _DotMatrixPainter({
    required this.text,
    required this.color,
    required this.dotPitch,
    required this.glow,
    required this.showGrid,
  });

  final String text;
  final Color color;
  final double dotPitch;
  final bool glow;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final dotR = dotPitch * 0.40; // round dots with clear air between them
    final lit = Paint()..color = color;
    final gridPaint = Paint()..color = color.withValues(alpha: 0.06);
    // Bloom sigma is PROPORTIONAL to the dot (not a fixed blur): a soft halo
    // roughly the dot's own size, so dots read as distinct lit points. A fixed
    // blur larger than the dot smears adjacent dots into a continuous shape
    // that looks like a fuzzy regular font — the bug this replaces.
    final bloom = glow
        ? (Paint()
            ..color = color.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, dotR * 0.9))
        : null;

    var originX = 0.0;
    for (final ch in text.split('')) {
      final glyph = _font[ch] ?? _blank;
      for (var row = 0; row < 7; row++) {
        final bits = glyph[row];
        for (var col = 0; col < 5; col++) {
          final on = (bits >> (4 - col)) & 1 == 1;
          if (!on && !showGrid) continue;
          final c = Offset(
            originX + col * dotPitch + dotPitch / 2,
            row * dotPitch + dotPitch / 2,
          );
          if (on) {
            if (bloom != null) canvas.drawCircle(c, dotR * 1.5, bloom);
            canvas.drawCircle(c, dotR, lit);
          } else {
            canvas.drawCircle(c, dotR * 0.7, gridPaint);
          }
        }
      }
      originX += 6 * dotPitch; // 5 dots + 1 gap
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) =>
      old.text != text ||
      old.color != color ||
      old.dotPitch != dotPitch ||
      old.glow != glow ||
      old.showGrid != showGrid;
}

/// Blank glyph (space / unknown character) — 5×7 of empty rows.
const List<int> _blank = [0, 0, 0, 0, 0, 0, 0];

/// 5×7 dot-matrix glyphs. Each entry is 7 rows top→bottom; each row is a 5-bit
/// mask where bit 4 (0x10) is the leftmost column. Covers exactly what the
/// readouts need: digits, A–Z, and `: . - + /` and space.
const Map<String, List<int>> _font = {
  ' ': _blank,
  '0': [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
  '1': [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
  '2': [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
  '3': [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
  '4': [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
  '5': [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
  '6': [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
  '7': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
  '8': [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
  '9': [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
  'A': [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'B': [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
  'C': [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
  'D': [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
  'E': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
  'F': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
  'G': [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
  'H': [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'I': [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
  'J': [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
  'K': [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
  'L': [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
  'M': [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
  'N': [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
  'O': [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'P': [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
  'Q': [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
  'R': [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
  'S': [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
  'T': [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
  'U': [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'V': [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
  'W': [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
  'X': [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
  'Y': [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
  'Z': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
  ':': [0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00],
  '.': [0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x04],
  '-': [0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00],
  '+': [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
  '/': [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10],
};
