import 'dart:async';

import 'package:anilocal/diagnostics/app_log.dart';
import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:anilocal/playback/media_remote.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/playback/playback_rules.dart';
import 'package:anilocal/ui/theater/zones/playback_session.dart';
import 'package:anilocal/ui/window_chrome.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_settings.dart';
import 'support/recording_player.dart';

const _s = Duration.new;

class _Settings extends FakeSettings {
  _Settings({
    this.skipMode = SkipMode.button,
    this.autoPlay = true,
    this.threshold = const Duration(seconds: 90),
  });
  SkipMode skipMode;
  bool autoPlay;
  Duration threshold;

  @override
  Future<SkipMode> loadSkipMode() async => skipMode;
  @override
  Future<bool> loadAutoPlayNext() async => autoPlay;
  @override
  Future<Duration> loadWatchedThreshold() async => threshold;
}

class _WatchState implements WatchStateRepository {
  bool applies = true;
  final marked = <Episode>[];
  final saved = <({Episode episode, Duration position})>[];

  @override
  Future<bool> setWatched(Episode episode, {required bool watched}) async {
    marked.add(episode);
    return applies;
  }

  @override
  Future<void> saveProgress(
    Episode episode, {
    required Duration position,
    required Duration duration,
  }) async {
    saved.add((episode: episode, position: position));
  }

  @override
  Future<void> setWatchedManual(Episode episode, {required bool watched}) =>
      throw UnimplementedError();
  @override
  Future<void> clearProgress(Episode episode) => throw UnimplementedError();
  @override
  Future<List<ContinueWatching>> continueWatching() =>
      throw UnimplementedError();
}

/// Resolves "next" from a fixed order; a test can hold one answer back with
/// [gates] to interleave two loads.
class _WatchOrder implements WatchOrderRepository {
  _WatchOrder(this.order);
  final List<Episode> order;
  final gates = <int, Completer<void>>{};

  @override
  Future<Map<int, Episode>> upNextBySeries() => throw UnimplementedError();

  @override
  Future<NextResult> nextEpisode(Episode current) async {
    await gates[current.anchoredNumber]?.future;
    final i = order.indexWhere(
      (e) => e.anchoredNumber == current.anchoredNumber,
    );
    if (i < 0 || i + 1 >= order.length) return const NoNextEpisode();
    return NextEpisode(order[i + 1]);
  }
}

Episode _episode(
  int n, {
  Duration resume = Duration.zero,
  SkipRange? intro,
  SkipRange? outro,
  SkipConfidence introConfidence = SkipConfidence.single,
  bool watched = false,
}) => Episode(
  number: n,
  anchoredNumber: n,
  seriesId: 7,
  fileRef: '/show/$n.mkv',
  resumePosition: resume,
  introSkip: intro,
  outroSkip: outro,
  introConfidence: introConfidence,
  watched: watched,
);

final _intro = SkipRange(start: Duration.zero, end: _s(seconds: 90));

class _Rig {
  _Rig({
    required List<Episode> episodes,
    _Settings? settings,
    Duration saveCadence = const Duration(seconds: 1),
  }) : settings = settings ?? _Settings(),
       watchOrder = _WatchOrder(episodes) {
    playback = PlaybackController.withPlayer(player, resolver: watchOrder);
    session = PlaybackSession(
      playback: playback,
      watchState: watchState,
      watchOrder: watchOrder,
      settings: this.settings,
      episode: episodes.first,
      onToggleFullscreen: () {},
      onEpisodeChanged: advanced.add,
      remoteFactory: _silentRemote,
      saveCadence: saveCadence,
    );
  }

  final player = RecordingPlayer();
  final watchState = _WatchState();
  final _Settings settings;
  final _WatchOrder watchOrder;
  late final PlaybackController playback;
  late final PlaybackSession session;
  final advanced = <Episode>[];

  static MediaRemote _silentRemote({
    required void Function() onPlay,
    required void Function() onPause,
    required void Function() onTogglePlayPause,
    required void Function() onNext,
  }) => MediaRemote.silent();
}

/// The playback SEQUENCING — which engine event may act when — over a
/// stand-in engine. The decisions themselves are `playback_rules_test`.
void main() {
  group('PlaybackSession', () {
    setUp(AppLog.reset);

    test('an overlay pauses; its going away resumes only what was playing', () {
      final rig = _Rig(episodes: [_episode(1)]);
      rig.session.start();
      rig.player.emitPlaying(true);
      rig.session.pauseForObscured();
      expect(rig.player.callCount(#pause), 1);
      rig.session.resumeIfObscurePaused();
      expect(rig.player.callCount(#play), 1, reason: 'it was playing');

      // Paused by the viewer before the overlay: stays paused after it.
      rig.player.emitPlaying(false);
      rig.session.pauseForObscured();
      rig.session.resumeIfObscurePaused();
      expect(rig.player.callCount(#play), 1, reason: 'not resumed');
    });

    test('Cmd-Q commits the position through the quit hook, awaited', () async {
      // The 1-second save timer has not fired; the runner asks to quit.
      final rig = _Rig(episodes: [_episode(1)]);
      rig.session.start();
      rig.player.emitDuration(_s(minutes: 24));
      rig.player.emitPosition(_s(minutes: 7));
      expect(rig.watchState.saved, isEmpty, reason: 'nothing saved yet');
      await WindowChrome.runQuitHooks();
      expect(rig.watchState.saved.single.position, _s(minutes: 7));
      await rig.session.dispose();
      // Removed with the session: a later quit must not touch a dead one.
      rig.watchState.saved.clear();
      await WindowChrome.runQuitHooks();
      expect(rig.watchState.saved, isEmpty);
    });

    test(
      'the phantom zero after open() cannot auto-skip over the resume point',
      () {
        fakeAsync((async) {
          final resumed = _episode(2, resume: _s(minutes: 20), intro: _intro);
          final rig = _Rig(
            episodes: [_episode(1), resumed],
            settings: _Settings(skipMode: SkipMode.auto),
          );
          rig.session.start();
          async.flushMicrotasks(); // ep 1 playing, auto mode loaded
          rig.session.select(resumed); // a rail tap
          // open() has already reported position 0 (see RecordingPlayer.open).
          // With the intro at 0s and auto mode live, that used to fire the skip
          // and seek to 1:30 — over the 20:00 the engine was about to resume at.
          expect(rig.player.seeks, isEmpty);
          async.flushMicrotasks();
          expect(rig.player.seeks, isEmpty);
          rig.player.emitPosition(_s(minutes: 20));
          expect(
            rig.player.seeks,
            isEmpty,
            reason: '20:00 is not in the intro',
          );
          rig.player.emitPosition(_s(seconds: 10)); // the viewer seeks back
          expect(
            rig.player.seeks,
            [_s(seconds: 90)],
            reason: 'a real position inside the window still fires',
          );
        });
      },
    );

    test('auto-skip fires once per window; a seek back offers the button', () {
      fakeAsync((async) {
        final rig = _Rig(
          episodes: [_episode(1, intro: _intro)],
          settings: _Settings(skipMode: SkipMode.auto),
        );
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitPosition(_s(seconds: 5));
        expect(rig.player.seeks, [_s(seconds: 90)]);
        rig.player.emitPosition(_s(seconds: 30)); // seeked back by hand
        expect(rig.player.seeks, hasLength(1), reason: 'not re-yanked');
        expect(rig.session.controls.value.showSkipIntro, isTrue);
      });
    });

    test('a conflicting window is offered, never fired, at the player', () {
      fakeAsync((async) {
        final rig = _Rig(
          episodes: [
            _episode(
              1,
              intro: _intro,
              introConfidence: SkipConfidence.conflicting,
            ),
          ],
          settings: _Settings(skipMode: SkipMode.auto),
        );
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitPosition(_s(seconds: 5));
        expect(rig.player.seeks, isEmpty);
        expect(rig.session.controls.value.showSkipIntro, isTrue);
      });
    });

    test('the outro skip stays short of the end, so it can never complete', () {
      fakeAsync((async) {
        final outro = SkipRange(
          start: _s(seconds: 1200),
          end: _s(seconds: 1290),
        );
        final rig = _Rig(
          episodes: [
            _episode(1, outro: outro),
            _episode(2),
          ],
          settings: _Settings(skipMode: SkipMode.auto),
        );
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitDuration(
          _s(seconds: 1280),
        ); // file ends inside the outro
        rig.player.emitPosition(_s(seconds: 1205));
        expect(rig.player.seeks, [_s(seconds: 1280) - kEndOfFileGuard]);
        expect(rig.player.opened, hasLength(1), reason: 'nothing advanced');
      });
    });

    test(
      'the pre-roll counts down, Cancel stops completion from advancing',
      () {
        fakeAsync((async) {
          final rig = _Rig(episodes: [_episode(1), _episode(2)]);
          rig.session.start();
          async.flushMicrotasks();
          rig.player.emitDuration(_s(seconds: 100));
          rig.player.emitPosition(_s(seconds: 90));
          expect(rig.session.controls.value.preRollShowing, isFalse);
          rig.player.emitPosition(_s(milliseconds: 96200));
          expect(rig.session.controls.value.preRollShowing, isTrue);
          expect(rig.session.controls.value.preRollSeconds, 4);
          expect(rig.session.controls.value.upNext?.number, 2);
          rig.player.emitPosition(_s(milliseconds: 97100));
          expect(rig.session.controls.value.preRollSeconds, 3);

          rig.session.cancelPreRoll();
          expect(rig.session.controls.value.preRollShowing, isFalse);
          rig.player.emitCompleted();
          async.flushMicrotasks();
          expect(
            rig.player.opened,
            hasLength(1),
            reason: 'cancelled = stop here',
          );
          expect(rig.advanced, isEmpty);
        });
      },
    );

    test(
      'completion advances when auto-play is on and nothing was cancelled',
      () {
        fakeAsync((async) {
          final rig = _Rig(
            episodes: [
              _episode(1),
              _episode(2, intro: _intro),
            ],
          );
          rig.session.start();
          async.flushMicrotasks();
          rig.player.emitDuration(_s(seconds: 100));
          rig.player.emitPosition(_s(seconds: 99));
          rig.player.emitCompleted();
          async.flushMicrotasks();
          expect(rig.player.opened.map((m) => m.uri), [
            '/show/1.mkv',
            '/show/2.mkv',
          ]);
          expect(rig.session.episode.number, 2);
          expect(rig.session.controls.value.episode?.number, 2);
          expect(rig.advanced.map((e) => e.number), [2]);
          expect(
            rig.watchState.marked.map((e) => e.number),
            [1],
            reason: 'the finished episode was marked on completion',
          );
          // A second completion event for the OLD file, arriving late, is inert.
          expect(
            rig.session.controls.value.upNext,
            isNull,
            reason: 'ep 2 is the last; no up-next',
          );
        });
      },
    );

    test(
      'two quick rail taps: the LAST tap wins even if its load finishes first',
      () {
        fakeAsync((async) {
          final eps = [_episode(1), _episode(2), _episode(3), _episode(4)];
          final rig = _Rig(episodes: eps);
          rig.session.start();
          async.flushMicrotasks();

          rig.watchOrder.gates[2] = Completer<void>(); // ep 2's "next" is slow
          rig.session.select(eps[1]);
          rig.session.select(eps[2]);
          async.flushMicrotasks();
          expect(rig.session.controls.value.episode?.number, 3);
          expect(rig.session.controls.value.upNext?.number, 4);

          rig.watchOrder.gates[2]!.complete(); // the loser's load lands late
          async.flushMicrotasks();
          expect(rig.session.controls.value.episode?.number, 3);
          expect(
            rig.session.controls.value.upNext?.number,
            4,
            reason: "ep 2's context (next = 3) must not overwrite ep 3's",
          );
        });
      },
    );

    test('settings changed over the player reach the playing episode', () {
      fakeAsync((async) {
        final rig = _Rig(
          episodes: [_episode(1, intro: _intro)],
          settings: _Settings(skipMode: SkipMode.button),
        );
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitPosition(_s(seconds: 5));
        expect(rig.player.seeks, isEmpty);

        rig.settings.skipMode = SkipMode.auto;
        unawaited(rig.session.reloadContext());
        async.flushMicrotasks();
        rig.player.emitPosition(_s(seconds: 6));
        expect(rig.player.seeks, [_s(seconds: 90)], reason: 'auto now applies');

        // Reloading does NOT re-arm a skip that already fired.
        unawaited(rig.session.reloadContext());
        async.flushMicrotasks();
        rig.player.emitPosition(_s(seconds: 7));
        expect(rig.player.seeks, hasLength(1));
      });
    });

    test(
      'a manual "unwatched" that refuses the auto mark keeps progress saving',
      () {
        fakeAsync((async) {
          final rig = _Rig(episodes: [_episode(1)]);
          rig.watchState.applies =
              false; // the repository says: manual override held
          rig.session.start();
          async.flushMicrotasks();
          rig.player.emitDuration(_s(minutes: 24));
          rig.player.emitPlaying(true);
          rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 91));
          rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 89));
          async.flushMicrotasks();
          expect(rig.watchState.marked, hasLength(1));

          rig.watchState.saved.clear();
          rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 60));
          async.elapse(_s(seconds: 1));
          expect(
            rig.watchState.saved.map((e) => e.position),
            [_s(minutes: 24) - _s(seconds: 60)],
            reason: 'resume keeps moving instead of freezing at the threshold',
          );
          expect(
            rig.watchState.marked,
            hasLength(1),
            reason: 'one attempt only',
          );
        });
      },
    );

    test('an applied watched mark ends progress saves for the episode', () {
      fakeAsync((async) {
        final rig = _Rig(episodes: [_episode(1)]);
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitDuration(_s(minutes: 24));
        rig.player.emitPlaying(true);
        rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 91));
        rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 89));
        async.flushMicrotasks();
        rig.watchState.saved.clear();
        rig.player.emitPosition(_s(minutes: 24) - _s(seconds: 60));
        async.elapse(_s(seconds: 3));
        expect(rig.watchState.saved, isEmpty);
      });
    });

    test('the periodic save is skipped while the position has not moved', () {
      fakeAsync((async) {
        final rig = _Rig(episodes: [_episode(1)]);
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitDuration(_s(minutes: 24));
        rig.player.emitPlaying(true);
        rig.player.emitPosition(_s(minutes: 5));
        async.elapse(_s(seconds: 5)); // five ticks, one position
        expect(rig.watchState.saved, hasLength(1));
        rig.player.emitPosition(_s(minutes: 5, seconds: 1));
        async.elapse(_s(seconds: 1));
        expect(rig.watchState.saved, hasLength(2));
      });
    });

    test('a paused scrub saves once, where the viewer let go', () {
      fakeAsync((async) {
        final rig = _Rig(episodes: [_episode(1)]);
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitDuration(_s(minutes: 24));
        rig.player.emitPlaying(false);
        for (var i = 1; i <= 20; i++) {
          rig.player.emitPosition(_s(seconds: 30 * i));
          async.elapse(const Duration(milliseconds: 20));
        }
        expect(rig.watchState.saved, isEmpty, reason: 'still settling');
        async.elapse(PlaybackSession.pausedSaveDebounce);
        expect(rig.watchState.saved.map((e) => e.position), [_s(seconds: 600)]);
        async.elapse(_s(seconds: 3));
        expect(
          rig.watchState.saved,
          hasLength(1),
          reason: 'the timer has nothing new to write while paused',
        );
      });
    });

    test('auto-play off: completion stops; threshold 0 never marks', () {
      fakeAsync((async) {
        final rig = _Rig(
          episodes: [_episode(1), _episode(2)],
          settings: _Settings(autoPlay: false, threshold: Duration.zero),
        );
        rig.session.start();
        async.flushMicrotasks();
        rig.player.emitDuration(_s(seconds: 100));
        rig.player.emitPlaying(true);
        rig.player.emitPosition(_s(seconds: 98));
        rig.player.emitPosition(_s(seconds: 99));
        expect(rig.session.controls.value.preRollShowing, isFalse);
        rig.player.emitCompleted();
        async.flushMicrotasks();
        expect(rig.player.opened, hasLength(1), reason: 'no auto-play');
        expect(rig.watchState.marked, isEmpty, reason: '0 = auto-watched off');
      });
    });

    test("the engine's error is shown over the frame and logged", () {
      fakeAsync((async) {
        final rig = _Rig(episodes: [_episode(1)]);
        rig.session.start();
        async.flushMicrotasks();
        expect(rig.session.controls.value.errorMessage, isNull);
        rig.player.emitError('Failed to open /show/1.mkv');
        expect(
          rig.session.controls.value.errorMessage,
          contains('/show/1.mkv'),
        );
        expect(AppLog.dump(), contains('Failed to open /show/1.mkv'));
        // The next open clears it.
        rig.session.select(_episode(2));
        async.flushMicrotasks();
        expect(rig.session.controls.value.errorMessage, isNull);
      });
    });

    test(
      'a watched episode opens from the start; an unwatched one resumes',
      () {
        fakeAsync((async) {
          final rig = _Rig(
            episodes: [
              _episode(1, resume: _s(minutes: 10), watched: true),
              _episode(2, resume: _s(minutes: 3)),
            ],
          );
          rig.session.start();
          async.flushMicrotasks();
          expect(rig.player.opened.single.extras, isNull);
          expect(rig.player.opened.single.start, isNull, reason: 'fresh');
          rig.session.select(rig.watchOrder.order[1]);
          async.flushMicrotasks();
          expect(rig.player.opened.last.start, _s(minutes: 3));
        });
      },
    );

    test(
      'dispose commits the position, stops the engine, never disposes it',
      () {
        fakeAsync((async) {
          final rig = _Rig(episodes: [_episode(1)]);
          rig.session.start();
          async.flushMicrotasks();
          rig.player.emitDuration(_s(minutes: 24));
          rig.player.emitPosition(_s(minutes: 7));
          unawaited(rig.session.dispose());
          async.flushMicrotasks();
          expect(rig.watchState.saved.last.position, _s(minutes: 7));
          expect(rig.player.called(#stop), isTrue);
          expect(rig.player.called(#dispose), isFalse);
          expect(rig.player.positionHasListener, isFalse);
        });
      },
    );
  });
}
