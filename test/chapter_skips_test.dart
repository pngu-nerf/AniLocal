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

  test('position only separates the two — the LATEST qualifying span on each '
      'side wins', () {
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(90),
      _at(400),
      _at(490),
      _at(1200),
      _at(1290),
    ], const Duration(seconds: 1400));

    // Spans are 90 / 310 / 90 / 710 / 90 / 110. Three qualify; the last
    // (1290-1400 = 110s) does not, so the latest QUALIFYING one wins on each
    // side. This asserted `0` for the opening until the live harness measured
    // it: two candidates before the midpoint means a cold open followed by the
    // real opening, five times out of five on the reference library.
    expect(
      skips?.intro?.start,
      const Duration(seconds: 400),
      reason: 'latest qualifying span before the midpoint',
    );
    expect(
      skips?.outro?.start,
      const Duration(seconds: 1200),
      reason: 'latest qualifying span after the midpoint',
    );
  });

  test('a COLD OPEN of theme-like length does not steal the opening', () {
    // `Boushoku no Berserk` ep5, verbatim from the live measurement: a first
    // chapter of 88s (inside the band) followed by the real opening at 88→178.
    // AniSkip independently says 87.9→177.9. Earliest-wins picked the cold open
    // and scored 0% overlap against that; this is the case the rule got wrong.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(88),
      _at(178),
      _at(1325),
    ], const Duration(milliseconds: 1415000));

    expect(skips?.intro?.start, const Duration(seconds: 88));
    expect(skips?.intro?.end, const Duration(seconds: 178));
  });

  test('a SINGLE candidate is unaffected by which side wins', () {
    // The case that justified earliest-wins in the first place, and the reason
    // flipping it is safe: episode 1 opening cold with its OP at 498s carries
    // exactly ONE qualifying span before the midpoint, so both rules agree.
    final skips = inferSkipsFromChapters([
      _at(0),
      _at(498),
      _at(588),
      _at(1331),
    ], const Duration(milliseconds: 1422100));

    expect(skips?.intro?.start, const Duration(seconds: 498));
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
