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

    test('beyond the tolerance is a CONFLICT, and never auto-skips', () {
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

    test('a disagreeing END alone is enough to conflict', () {
      final result = reconcileSkips([
        _answer('a', intro: _r(0, 90)),
        _answer('b', intro: _r(0, 130)),
      ]);

      expect(result.intro?.confidence, SkipConfidence.conflicting);
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
