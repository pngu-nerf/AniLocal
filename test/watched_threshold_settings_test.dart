import 'package:anilocal/domain/repositories/settings_repository.dart';
import 'package:anilocal/ui/settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The watched-threshold min:sec parser is the single gate that keeps a
/// blank/garbage value out of the persisted setting. These lock its contract:
/// accept well-formed `m:ss` up to 9:59, reject everything else.
void main() {
  group('parseWatchedThreshold', () {
    test('accepts well-formed m:ss', () {
      expect(parseWatchedThreshold('1:30'), const Duration(seconds: 90));
      expect(parseWatchedThreshold('0:00'), Duration.zero);
      expect(parseWatchedThreshold('9:59'), watchedThresholdMax);
      expect(parseWatchedThreshold('0:05'), const Duration(seconds: 5));
    });

    test('trims surrounding whitespace', () {
      expect(parseWatchedThreshold('  1:30  '), const Duration(seconds: 90));
    });

    test('accepts single-digit seconds leniently (1:5 = 1m05s)', () {
      expect(parseWatchedThreshold('1:5'), const Duration(seconds: 65));
    });

    test('rejects seconds >= 60', () {
      expect(parseWatchedThreshold('1:60'), isNull);
      expect(parseWatchedThreshold('0:99'), isNull);
    });

    test('rejects values past the 9:59 cap', () {
      expect(parseWatchedThreshold('10:00'), isNull);
      expect(parseWatchedThreshold('12:30'), isNull);
    });

    test('rejects non-numeric / malformed / blank input', () {
      expect(parseWatchedThreshold(''), isNull);
      expect(parseWatchedThreshold('abc'), isNull);
      expect(parseWatchedThreshold('130'), isNull); // no colon
      expect(parseWatchedThreshold('1:'), isNull);
      expect(parseWatchedThreshold(':30'), isNull);
      expect(parseWatchedThreshold('1:2:3'), isNull);
      expect(parseWatchedThreshold('-1:00'), isNull); // negative
    });
  });

  group('formatWatchedThreshold', () {
    test('renders m:ss with zero-padded seconds', () {
      expect(formatWatchedThreshold(const Duration(seconds: 90)), '1:30');
      expect(formatWatchedThreshold(Duration.zero), '0:00');
      expect(formatWatchedThreshold(watchedThresholdMax), '9:59');
      expect(formatWatchedThreshold(const Duration(seconds: 5)), '0:05');
    });

    test('round-trips through the parser', () {
      for (final d in [
        Duration.zero,
        const Duration(seconds: 90),
        const Duration(minutes: 3, seconds: 7),
        watchedThresholdMax,
      ]) {
        expect(parseWatchedThreshold(formatWatchedThreshold(d)), d);
      }
    });
  });
}
