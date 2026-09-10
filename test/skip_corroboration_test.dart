import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:flutter_test/flutter_test.dart';

SkipRange _r(int startS, int endS) => SkipRange(
  start: Duration(seconds: startS),
  end: Duration(seconds: endS),
);

({String source, EpisodeSkips skips}) _answer(
  String source, {
  SkipRange? intro,
  SkipRange? outro,
}) => (source: source, skips: EpisodeSkips(intro: intro, outro: outro));

void main() {
  group('silence is not disagreement', () {
    test('a source with NO window for this episode does not count against it', () {
      // The rule that matters most. Partial coverage is the norm for skip data,
      // so if an absent answer counted as dissent almost everything would be
      // marked conflicting and auto-skip would switch itself off library-wide.
      final result = reconcileSkips([
        _answer('aniskip', intro: _r(0, 90)),
        _answer('chapters'), // knows this episode, has no windows for it
      ]);

      expect(result.intro?.confidence, SkipConfidence.single);
      expect(result.intro?.confidence.allowsAutoSkip, isTrue);
    });

    test('a source with only an OUTRO does not weigh in on the intro', () {
      // Judged per window: chapters supply an ending here and say nothing about
      // the opening, so the opening remains a single-source window rather than
      // being dragged to conflicting.
      final result = reconcileSkips([
        _answer('aniskip', intro: _r(0, 90), outro: _r(1330, 1420)),
        _answer('chapters', outro: _r(1331, 1421)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.single);
      expect(result.outro?.confidence, SkipConfidence.corroborated);
    });

    test('one source answering alone is normal, not doubt', () {
      final result = reconcileSkips([_answer('chapters', intro: _r(498, 588))]);

      expect(result.intro?.confidence, SkipConfidence.single);
      expect(result.intro?.source, 'chapters');
    });
  });

  group('agreement', () {
    test('two independent sources within tolerance corroborate', () {
      // Real numbers: AniSkip and the release group's chapters agreed to about
      // half a second on the reference library.
      final result = reconcileSkips([
        _answer('aniskip', intro: _r(498, 588)),
        _answer('chapters', intro: _r(497, 588)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.corroborated);
      expect(result.intro?.confidence.allowsAutoSkip, isTrue);
    });

    test('exactly at the tolerance still agrees', () {
      final result = reconcileSkips([
        _answer('a', intro: _r(500, 590)),
        _answer('b', intro: _r(502, 592)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.corroborated);
    });

    test('a window in a different PLACE conflicts, and never auto-skips', () {
      final result = reconcileSkips([
        _answer('aniskip', intro: _r(0, 90)),
        _answer('chapters', intro: _r(60, 150)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.conflicting);
      expect(
        result.intro?.confidence.allowsAutoSkip,
        isFalse,
        reason: 'a window we cannot vouch for must not fire on its own',
      );
    });

    test('edges may differ — what matters is WHERE the theme is', () {
      // Real pairs from the reference library, all previously condemned by the
      // ±2s edge rule. Each is the same theme with a legitimately different
      // boundary, and the leading source supplies the times regardless.
      const cases = <(String, SkipRange, SkipRange)>[
        // AniSkip's submission targeted a different release: uniform ~5s late.
        (
          'Cyberpunk ep2, 5.2s offset',
          SkipRange(
            start: Duration(milliseconds: 71000),
            end: Duration(milliseconds: 161000),
          ),
          SkipRange(
            start: Duration(milliseconds: 76168),
            end: Duration(milliseconds: 166168),
          ),
        ),
        // The chapter bundles a streaming ident in with the opening.
        (
          'Cyberpunk ep3, ident bundled',
          SkipRange(start: Duration.zero, end: Duration(milliseconds: 95600)),
          SkipRange(
            start: Duration(milliseconds: 11300),
            end: Duration(milliseconds: 101300),
          ),
        ),
        // Start agreed within a second; AniSkip's credits ran ~4s longer.
        (
          'Ore dake ep6 outro, long end',
          SkipRange(
            start: Duration(milliseconds: 1326000),
            end: Duration(milliseconds: 1416000),
          ),
          SkipRange(
            start: Duration(milliseconds: 1325000),
            end: Duration(milliseconds: 1420100),
          ),
        ),
        // Same end, 38s different start — the loosest real pair, 70%.
        (
          'Sakamoto ep11, loosest real pair',
          SkipRange(
            start: Duration(milliseconds: 38000),
            end: Duration(milliseconds: 128000),
          ),
          SkipRange(start: Duration.zero, end: Duration(milliseconds: 128100)),
        ),
      ];
      for (final (label, a, b) in cases) {
        expect(
          reconcileSkips([
            _answer('chapters', intro: a),
            _answer('aniskip', intro: b),
          ]).intro?.confidence,
          SkipConfidence.corroborated,
          reason: label,
        );
      }
    });

    test('a genuinely DIFFERENT place still conflicts', () {
      // Also real, and every one of these was the leading source having picked
      // a cold open of theme-like length while the true opening began where
      // that window ended. Refusing to auto-skip these is the whole point.
      const cases = <(String, SkipRange, SkipRange)>[
        (
          'Boushoku ep5, adjacent not equal',
          SkipRange(start: Duration.zero, end: Duration(milliseconds: 88000)),
          SkipRange(
            start: Duration(milliseconds: 87900),
            end: Duration(milliseconds: 177900),
          ),
        ),
        (
          'Sakamoto ep5, 126s apart',
          SkipRange(start: Duration.zero, end: Duration(milliseconds: 86000)),
          SkipRange(
            start: Duration(milliseconds: 125800),
            end: Duration(milliseconds: 210800),
          ),
        ),
        (
          'Boushoku ep1, 60s apart',
          SkipRange(
            start: Duration(milliseconds: 35000),
            end: Duration(milliseconds: 125000),
          ),
          SkipRange(
            start: Duration(milliseconds: 95500),
            end: Duration(milliseconds: 185500),
          ),
        ),
        (
          'Sakamoto ep2, tightest real conflict',
          SkipRange(
            start: Duration(milliseconds: 38000),
            end: Duration(milliseconds: 127800),
          ),
          SkipRange(
            start: Duration(milliseconds: 2700),
            end: Duration(milliseconds: 92700),
          ),
        ),
      ];
      for (final (label, a, b) in cases) {
        expect(
          reconcileSkips([
            _answer('chapters', intro: a),
            _answer('aniskip', intro: b),
          ]).intro?.confidence,
          SkipConfidence.conflicting,
          reason: label,
        );
      }
    });

    test('a wildly different LENGTH is a disagreement too', () {
      // Overlap is intersection over UNION, so it penalises a mismatched length
      // and not only a shifted window. One source calling the theme 90s and
      // another 200s is not agreement, even though they start together.
      expect(
        reconcileSkips([
          _answer('a', intro: _r(0, 90)),
          _answer('b', intro: _r(0, 200)),
        ]).intro?.confidence,
        SkipConfidence.conflicting,
      );
    });

    test('the threshold sits in an EMPTY band, so it is not tuned', () {
      // Across all 59 disagreeing pairs on the reference library, none landed
      // between 45% and 69% overlap: 50 were 70-97%, 9 were 0-44%. Assert
      // against the named constant rather than a literal, so moving it cannot
      // silently invalidate the cases above.
      expect(kSkipCorroborationMinOverlap, greaterThan(0.45));
      expect(kSkipCorroborationMinOverlap, lessThan(0.70));
      // And the metric itself: identical windows agree totally, disjoint ones
      // not at all.
      expect(windowOverlap(_r(0, 90), _r(0, 90)), 1.0);
      expect(windowOverlap(_r(0, 90), _r(200, 290)), 0.0);
      expect(windowOverlap(_r(0, 90), _r(45, 135)), closeTo(1 / 3, 0.001));
    });

    test('agreement with ANY source is enough — one outlier cannot veto', () {
      final result = reconcileSkips([
        _answer('a', intro: _r(0, 90)),
        _answer('b', intro: _r(600, 700)), // nonsense
        _answer('c', intro: _r(0, 91)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.corroborated);
    });
  });

  group('which window is used', () {
    test('the highest-priority source supplies the times, always', () {
      // Corroboration decides how much to TRUST a window, never which one to
      // use — so reordering sources still determines what you get.
      final result = reconcileSkips([
        _answer('chapters', intro: _r(497, 588)),
        _answer('aniskip', intro: _r(498, 589)),
      ]);

      expect(result.intro?.source, 'chapters');
      expect(result.intro?.range.start, const Duration(seconds: 497));
    });

    test('that holds even when they conflict', () {
      final result = reconcileSkips([
        _answer('chapters', intro: _r(0, 90)),
        _answer('aniskip', intro: _r(600, 690)),
      ]);

      expect(result.intro?.source, 'chapters');
      expect(result.intro?.confidence, SkipConfidence.conflicting);
    });
  });

  group('the minimum-length floor', () {
    test('a window shorter than the floor is dropped', () {
      // Sources occasionally mark a few-second sting or scene divider; offering
      // that as "skip the intro" is noise at best.
      expect(dropIfShorterThan(_r(0, 5), const Duration(seconds: 30)), isNull);
    });

    test('a real opening is kept', () {
      final op = _r(0, 90);
      expect(dropIfShorterThan(op, const Duration(seconds: 30)), same(op));
    });

    test(
      'exactly at the floor is kept — the floor is a minimum, not a gap',
      () {
        final window = _r(0, 30);
        expect(
          dropIfShorterThan(window, const Duration(seconds: 30)),
          same(window),
        );
      },
    );

    test('a floor of zero keeps everything — the default changes nothing', () {
      final tiny = _r(0, 2);
      expect(dropIfShorterThan(tiny, Duration.zero), same(tiny));
    });

    test('a null window stays null', () {
      expect(dropIfShorterThan(null, const Duration(seconds: 30)), isNull);
    });
  });

  test('no answers at all yields nothing', () {
    expect(reconcileSkips(const []).isEmpty, isTrue);
    expect(reconcileSkips([_answer('a')]).isEmpty, isTrue);
  });

  test('confidence round-trips through its stored form', () {
    for (final c in SkipConfidence.values) {
      expect(SkipConfidence.fromStored(c.stored), c);
    }
    expect(
      SkipConfidence.fromStored(99),
      SkipConfidence.single,
      reason: 'an unknown stored value must degrade to the neutral verdict',
    );
  });
}
