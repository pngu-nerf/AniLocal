import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../diagnostics/app_log.dart';
import '../domain/models/episode.dart';
import '../domain/models/next_result.dart';
import '../domain/repositories/watch_order_repository.dart';
import 'player_configuration.dart';

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
/// - [dispose] — releases native resources; the controller is TERMINAL
///   afterwards. Called once, by the app-lifetime owner (`_AppLifetime` in
///   `app.dart`) when the widget tree is torn down — which on a desktop quit
///   usually never happens, and the OS reclaims the process instead. It is
///   there so that a teardown that DOES run releases the engine rather than
///   leaking it; nothing else may call it.
///
/// (media_kit README on `stop()`: "It does not release allocated resources back
/// to the system (unlike `dispose`) & `Player` still stays usable.")
class PlaybackController {
  PlaybackController({
    required this.resolver,
    this.configuration = kPlayerConfiguration,
  });

  /// A controller over an already-built [player] — for tests, which have no
  /// libmpv. The [VideoController] is NOT built on this path, so [controller]
  /// must not be read; everything else (open, seek, streams, advance, stop,
  /// dispose) behaves exactly as in production.
  @visibleForTesting
  PlaybackController.withPlayer(Player player, {required this.resolver})
    : configuration = kPlayerConfiguration,
      _player = player;

  /// The one libmpv configuration — see [kPlayerConfiguration].
  final PlayerConfiguration configuration;

  Player? _player;
  VideoController? _controller;
  StreamSubscription<PlayerLog>? _logSub;
  bool _disposed = false;

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
    if (_disposed) {
      throw StateError('PlaybackController used after dispose()');
    }
    if (_player != null) return;
    final p = Player(configuration: configuration);
    _player = p;
    // mpv's own warnings and errors into the diagnostics ring, so a decoder
    // failure or a missing codec is in "Copy diagnostics" rather than lost.
    _logSub = p.stream.log.listen(
      (l) => AppLog.warn('mpv ${l.prefix} [${l.level}] ${l.text}'),
    );
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

  Future<Episode?>? _advancing;

  /// THE advance-to-next action — one entry point, callable by any trigger
  /// (the auto-play countdown, the completion event, "Play next", the media
  /// remote's next, seeking past the end). Asks the resolver what follows
  /// [current]: if there's a next episode it plays it and returns it; at a
  /// season boundary ([NoNextEpisode]) it stops and returns null. Advancing
  /// never computes "next" itself — it routes through the resolver like every
  /// other caller.
  ///
  /// RE-ENTRANT CALLS JOIN THE ONE IN FLIGHT. Five triggers can fire within the
  /// same second at the end of an episode (the countdown reaching zero, the
  /// completion event, a held → key repeating, a media-remote "next"); each
  /// resolving "next" from the same [current] and opening it would open the
  /// same episode several times, or — once the first had moved [current] on —
  /// skip an episode outright. While an advance is in flight every further
  /// call gets the same future and causes nothing.
  Future<Episode?> advanceToNext() {
    final inFlight = _advancing;
    if (inFlight != null) return inFlight;
    final run = _advance().whenComplete(() => _advancing = null);
    _advancing = run;
    return run;
  }

  Future<Episode?> _advance() async {
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

  /// Release the native engine. **The app-lifetime owner only, once** — see
  /// the class doc. TERMINAL: any later use throws instead of quietly building
  /// a second engine, which is what an accidental post-dispose `player` read
  /// used to do.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _current = null;
    await _logSub?.cancel();
    _logSub = null;
    final p = _player;
    _player = null;
    _controller = null;
    await p?.dispose();
  }
}
