import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:anilocal/playback/playback_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The player's decisions as pure functions — each rule pinned by the number
/// it turns on, with no engine in the room.
void main() {
  const s = Duration.new;
  final outro = SkipRange(start: s(seconds: 1200), end: s(seconds: 1290));

  group('outroSeekTarget', () {
    test('lands at the window end when the file continues past it', () {
      expect(
        outroSeekTarget(
          outro: outro,
          duration: s(seconds: 1400),
          position: s(seconds: 1205),
        ),
        s(seconds: 1290),
      );
    });

    test('stops SHORT of the end when the window overhangs the file', () {
      // A seek to exactly the duration reaches EOF, which the app reads as
      // "finished" and advances — the outro skip must never do that.
      final target = outroSeekTarget(
        outro: outro,
        duration: s(seconds: 1280),
        position: s(seconds: 1205),
      );
      expect(target, s(seconds: 1280) - kEndOfFileGuard);
      expect(target, lessThan(s(seconds: 1280)));
    });

    test('is a no-op behind the current position, never a backward jump', () {
      expect(
        outroSeekTarget(
          outro: outro,
          duration: s(seconds: 1280),
          position: s(seconds: 1285),
        ),
        isNull,
      );
    });

    test('trusts the window while the duration is unknown', () {
      expect(
        outroSeekTarget(
          outro: outro,
          duration: Duration.zero,
          position: s(seconds: 1205),
        ),
        s(seconds: 1290),
      );
    });
  });

  group('shouldMarkFromPlayback', () {
    const dur = Duration(minutes: 24);
    const threshold = Duration(seconds: 90);

    test('a small forward step into the threshold window marks', () {
      expect(
        shouldMarkFromPlayback(
          previous: dur - s(seconds: 91),
          position: dur - s(seconds: 90),
          duration: dur,
          threshold: threshold,
        ),
        isTrue,
      );
    });

    test('a jump is a seek and never marks', () {
      expect(
        shouldMarkFromPlayback(
          previous: s(minutes: 5),
          position: dur - s(seconds: 30),
          duration: dur,
          threshold: threshold,
        ),
        isFalse,
      );
      expect(
        shouldMarkFromPlayback(
          previous: dur - s(seconds: 10),
          position: dur - s(seconds: 30),
          duration: dur,
          threshold: threshold,
        ),
        isFalse,
        reason: 'backward is a seek',
      );
    });

    test('the seek boundary scales with the playback rate', () {
      // 3s of media between events: a seek at 1×, ordinary playback at 2×.
      final previous = dur - s(seconds: 33);
      final position = dur - s(seconds: 30);
      expect(
        shouldMarkFromPlayback(
          previous: previous,
          position: position,
          duration: dur,
          threshold: threshold,
        ),
        isFalse,
      );
      expect(
        shouldMarkFromPlayback(
          previous: previous,
          position: position,
          duration: dur,
          threshold: threshold,
          rate: 2.0,
        ),
        isTrue,
      );
    });

    test('a zero threshold is the master off-switch', () {
      expect(
        shouldMarkFromPlayback(
          previous: dur - s(seconds: 2),
          position: dur - s(seconds: 1),
          duration: dur,
          threshold: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  test('wholeEpisodeWithinThreshold', () {
    expect(
      wholeEpisodeWithinThreshold(
        duration: s(seconds: 60),
        threshold: s(seconds: 90),
      ),
      isTrue,
    );
    expect(
      wholeEpisodeWithinThreshold(
        duration: s(seconds: 91),
        threshold: s(seconds: 90),
      ),
      isFalse,
    );
    expect(
      wholeEpisodeWithinThreshold(
        duration: Duration.zero,
        threshold: s(seconds: 90),
      ),
      isFalse,
      reason: 'unknown duration is not "short"',
    );
  });

  group('preRollSecondsFor', () {
    test('is live only inside the lead, counting whole seconds up', () {
      expect(preRollSecondsFor(s(seconds: 6)), isNull);
      expect(preRollSecondsFor(s(seconds: 5)), 5);
      expect(preRollSecondsFor(s(milliseconds: 4200)), 5);
      expect(preRollSecondsFor(s(milliseconds: 3001)), 4);
      expect(preRollSecondsFor(s(milliseconds: 300)), 1);
      expect(preRollSecondsFor(Duration.zero), isNull);
      expect(preRollSecondsFor(s(seconds: -1)), isNull);
    });
  });

  group('decideSkips', () {
    final intro = SkipRange(start: Duration.zero, end: s(seconds: 90));
    Episode episode({
      SkipConfidence intro = SkipConfidence.single,
      SkipConfidence outro = SkipConfidence.single,
    }) => Episode(
      number: 1,
      fileRef: '/a.mkv',
      introSkip: SkipRange(start: Duration.zero, end: s(seconds: 90)),
      outroSkip: SkipRange(start: s(seconds: 1200), end: s(seconds: 1290)),
      introConfidence: intro,
      outroConfidence: outro,
    );

    SkipDecision at(
      Duration pos, {
      SkipMode mode = SkipMode.auto,
      Episode? ep,
      bool introSkipped = false,
      bool outroSkipped = false,
      bool preRoll = false,
    }) => decideSkips(
      mode: mode,
      episode: ep ?? episode(),
      position: pos,
      introSkipped: introSkipped,
      outroSkipped: outroSkipped,
      preRollShowing: preRoll,
    );

    test('off: nothing fires, nothing is offered', () {
      final d = at(s(seconds: 10), mode: SkipMode.off);
      expect(d.auto, AutoSkip.none);
      expect(d.showIntroButton, isFalse);
    });

    test('button: offered inside the window only', () {
      expect(at(s(seconds: 10), mode: SkipMode.button).showIntroButton, isTrue);
      expect(at(intro.end, mode: SkipMode.button).showIntroButton, isFalse);
      expect(at(s(seconds: 10), mode: SkipMode.button).auto, AutoSkip.none);
    });

    test('auto fires ONCE per window; after that the button is offered', () {
      expect(at(s(seconds: 10)).auto, AutoSkip.intro);
      final again = at(s(seconds: 10), introSkipped: true);
      expect(again.auto, AutoSkip.none, reason: 'a seek back is not re-yanked');
      expect(again.showIntroButton, isTrue);
    });

    test('a CONFLICTING window is offered but never fired', () {
      final d = at(
        s(seconds: 10),
        ep: episode(intro: SkipConfidence.conflicting),
      );
      expect(d.auto, AutoSkip.none);
      expect(d.showIntroButton, isTrue);
    });

    test('the outro button yields to the up-next pre-roll', () {
      expect(
        at(s(seconds: 1250), mode: SkipMode.button).showOutroButton,
        isTrue,
      );
      expect(
        at(
          s(seconds: 1250),
          mode: SkipMode.button,
          preRoll: true,
        ).showOutroButton,
        isFalse,
      );
    });
  });
}
