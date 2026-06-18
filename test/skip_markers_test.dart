import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
import 'package:flutter_test/flutter_test.dart';

const _min = Duration(minutes: 1);

void main() {
  group('skipSpanFraction (timeline markers)', () {
    test('a normal window maps to its fraction of the duration', () {
      // intro 1:00–2:00 of a 10:00 episode.
      final span = skipSpanFraction(
        const SkipRange(start: _min, end: Duration(minutes: 2)),
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(span, isNotNull);
      expect(span!.start, closeTo(0.1, 1e-9));
      expect(span.end, closeTo(0.2, 1e-9));
    });

    test('an outro overhanging the file end clamps to 1.0', () {
      // outro 9:00–11:00 of a 10:00 file — end must clamp, never exceed 1.
      final span = skipSpanFraction(
        const SkipRange(
          start: Duration(minutes: 9),
          end: Duration(minutes: 11),
        ),
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(span, isNotNull);
      expect(span!.start, closeTo(0.9, 1e-9));
      expect(span.end, 1.0);
    });

    test('a null window draws nothing', () {
      expect(
        skipSpanFraction(null, const Duration(minutes: 10).inMilliseconds),
        isNull,
      );
    });

    test('unknown duration (0) draws nothing', () {
      expect(
        skipSpanFraction(
          const SkipRange(start: _min, end: Duration(minutes: 2)),
          0,
        ),
        isNull,
      );
    });

    test('a window entirely past the end is degenerate -> nothing', () {
      // Both bounds clamp to 1.0 -> start == end -> null.
      final span = skipSpanFraction(
        const SkipRange(
          start: Duration(minutes: 12),
          end: Duration(minutes: 13),
        ),
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(span, isNull);
    });
  });
}
