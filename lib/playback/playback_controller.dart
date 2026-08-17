import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';
import '../domain/models/next_result.dart';
import '../domain/repositories/watch_order_repository.dart';

/// Thin wrapper around media_kit's [Player] + [VideoController] (libmpv).
///
/// The single place that owns playback engine objects. The UI hands it a domain
/// [Episode] — never a raw path or a data-layer type — and gets a
/// [VideoController] to render plus position/duration/completed streams. It also
/// owns the one advance-to-next action ([advanceToNext]).
///
/// **APP-LIFETIME, not route-lifetime.** This is constructed ONCE at the
/// composition root (`main.dart`) and injected, so the engine outlives
/// navigation. It used to be built in `VideoZone.initState` and torn down on
/// every theater pop, which meant a full libmpv construct/destroy per visit —
/// and each destroy is a roll of the dice against a known media_kit/Dart-VM FFI
/// teardown race (`Callback invoked after it has been deleted`; media-kit issues
/// #1324/#1314/#1397). One engine per app run replaces one per visit.
///
/// Consequently the two shutdown verbs are NOT interchangeable:
/// - [stop] — the user LEFT playback. Playback ends, the `Player` stays usable
///   for the next episode. This is what a route pop does now.
/// - [dispose] — releases native resources; the `Player` is dead afterwards.
///   Called EXACTLY ONCE, by the composition root, at app shutdown.
///
/// (media_kit README on `stop()`: "It does not release allocated resources back
/// to the system (unlike `dispose`) & `Player` still stays usable.")
class PlaybackController {
  PlaybackController({required this.resolver});

  Player? _player;
  VideoController? _controller;

  /// Build the engine on FIRST USE, not at construction.
  ///
  /// App-lifetime ownership must not mean "libmpv starts when the app starts":
  /// this object is created at the composition root, and eagerly constructing
  /// `Player()` there would move native init into cold start and make a libmpv
  /// failure break the whole app instead of just playback. Lazy keeps the OLD
  /// timing exactly — the engine is born the first time something plays — while
  /// the OWNERSHIP moves up. (It also keeps the composition root constructible
  /// in the test harness, which has no libmpv.)
  ///
  /// Player-then-VideoController, in that order, in one step: the same order
  /// the eager constructor used, so the controller is always attached before
  /// any [open].
  void _ensureEngine() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _controller = VideoController(p);
  }

  Player get player {
    _ensureEngine();
    return _player!;
  }

  VideoController get controller {
    _ensureEngine();
    return _controller!;
  }

  /// Single source of "what's next" — consulted by [advanceToNext].
  final WatchOrderRepository resolver;

  Episode? _current;

  /// The episode currently loaded (null before the first [open]).
  Episode? get current => _current;

  /// Play [episode], resuming at [startAt]. media_kit normalizes the plain path
  /// for libmpv — robust to spaces and `[brackets]` in release filenames.
  Future<void> open(Episode episode, {Duration startAt = Duration.zero}) {
    _current = episode;
    return player.open(
      Media(episode.fileRef, start: startAt > Duration.zero ? startAt : null),
    );
  }

  /// Where playback should START for [e]: a WATCHED/complete episode always
  /// plays fresh from the BEGINNING (its saved resume position is ignored — not
  /// cleared — so a re-watch never drops the viewer near the end); an unwatched
  /// episode resumes where it left off. The single source of this rule so every
  /// open path (initial, list-swap, auto-advance) behaves identically.
  static Duration resumeStartFor(Episode e) =>
      e.watched ? Duration.zero : e.resumePosition;

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;

  /// Emits `true` when the current media finishes.
  Stream<bool> get completedStream => player.stream.completed;

  /// Seek within the current media — used to skip an intro to its end.
  Future<void> seekTo(Duration position) => player.seek(position);

  /// THE advance-to-next action — one entry point, callable by any trigger
  /// (the auto-play countdown today; a future "seek past the end" handler).
  /// Asks the resolver what follows [current]: if there's a next episode it
  /// plays it and returns it; at a season boundary ([NoNextEpisode]) it stops
  /// and returns null. Advancing never computes "next" itself — it routes
  /// through the resolver like every other caller.
  Future<Episode?> advanceToNext() async {
    final cur = _current;
    if (cur == null) return null;
    final result = await resolver.nextEpisode(cur);
    if (result is NextEpisode) {
      await open(result.episode, startAt: resumeStartFor(result.episode));
      return result.episode;
    }
    return null; // NoNextEpisode -> stop
  }

  /// The user left playback (theater pop). Stops the media and forgets the
  /// current episode, but KEEPS the engine alive and usable for re-entry — the
  /// whole point of app-lifetime ownership. Never call [dispose] here.
  /// No-op if nothing ever played — stopping must not be the thing that
  /// constructs the engine.
  Future<void> stop() async {
    _current = null;
    await _player?.stop();
  }

  /// Release the native engine. **Composition root only, once, at app
  /// shutdown** — see the class doc. Calling this on a route pop is the
  /// behaviour this rearchitecture removed.
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _controller = null;
  }
}
