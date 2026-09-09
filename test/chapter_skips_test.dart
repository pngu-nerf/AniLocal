import 'package:anilocal/domain/chapter_skips.dart';
import 'package:flutter_test/flutter_test.dart';

/// The riskiest code in the skip family: a wrong window here doesn't lose data,
/// it SKIPS NINETY SECONDS OF THE EPISODE. So these lean on declining rather
/// than guessing.
ChapterMark _at(int seconds) => ChapterMark(start: Duration(seconds: seconds));

void main() {
  const episode = Duration(minutes: 24); // 1440s

  test('an opening at the very start is found', () {
    // Real shape from the reference library: 0 / 90 / 791.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(90),
      _at(791),
    ], const Duration(milliseconds: 1420086));

    expect(skips?.intro?.start, Duration.zero);
    expect(skips?.intro?.end, const Duration(seconds: 90));
  });

  test('an opening after a COLD OPEN is found just the same', () {
    // Also real: episode 1 of the same show opens cold and starts the OP at
    // 498s while episodes 2 and 3 start it at 0. Any rule keyed on "the first
    // chapter" would be wrong immediately, which is why length decides.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(498),
      _at(588),
      _at(1331),
    ], const Duration(milliseconds: 1422100));

    expect(skips?.intro?.start, const Duration(seconds: 498));
    expect(skips?.intro?.end, const Duration(seconds: 588));
  });

  test('an ending near the end is found', () {
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(90),
      _at(1330),
    ], const Duration(seconds: 1420));

    expect(skips?.outro?.start, const Duration(seconds: 1330));
    expect(skips?.outro?.end, const Duration(seconds: 1420));
  });

  test('the last chapter is closed with the FILE DURATION', () {
    // Containers store starts only. Without the duration the final chapter has
    // no end and the ED could never be measured at all.
    final skips = inferSkipsFromChapters([_at(0), _at(1350)], episode);

    expect(skips?.outro?.end, episode);
  });

  test('a scene-length chapter is NOT mistaken for a theme', () {
    // Chapters that merely divide scenes must produce nothing. Offering a
    // plausible-looking wrong skip is worse than offering none.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(300),
      _at(700),
      _at(1100),
    ], episode);

    expect(skips, isNull);
  });

  test('a chapter just outside the band is rejected', () {
    for (final length in [70, 84, 101, 130]) {
      final skips = inferSkipsFromChapters([_at(0), _at(length)], episode);
      expect(
        skips?.intro,
        isNull,
        reason: '${length}s should not read as an opening',
      );
    }
  });

  test('both windows are found when both are present', () {
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(498),
      _at(588),
      _at(1331),
    ], const Duration(seconds: 1421));

    expect(skips?.intro?.start, const Duration(seconds: 498));
    expect(skips?.outro?.start, const Duration(seconds: 1331));
  });

  test('position only separates the two — the EARLIEST before the midpoint '
      'and the LATEST after it win', () {
    // A repeated ~90s span mid-episode is a scene, not a second opening.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(90),
      _at(400),
      _at(490),
      _at(1200),
      _at(1290),
    ], const Duration(seconds: 1400));

    // Spans are 90 / 310 / 90 / 710 / 90 / 110. Three qualify; the last
    // (1290-1400 = 110s) does not, so the latest QUALIFYING one wins.
    expect(skips?.intro?.start, Duration.zero, reason: 'earliest before mid');
    expect(
      skips?.outro?.start,
      const Duration(seconds: 1200),
      reason: 'latest qualifying span after the midpoint',
    );
  });

  test('no chapters, or no duration, means no answer', () {
    expect(inferSkipsFromChapters(const [], episode), isNull);
    expect(inferSkipsFromChapters([_at(0), _at(90)], Duration.zero), isNull);
  });

  test('unsorted marks are handled', () {
    final skips = inferSkipsFromChapters([_at(90), _at(0), _at(791)], episode);

    expect(skips?.intro?.start, Duration.zero);
  });

  test('a single mark yields nothing on its own', () {
    // One mark plus the duration is one span covering the whole episode.
    expect(inferSkipsFromChapters([_at(0)], episode), isNull);
  });
}
