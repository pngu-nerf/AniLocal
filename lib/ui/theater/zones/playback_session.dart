import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../diagnostics/app_log.dart';
import '../../../domain/models/episode.dart';
import '../../../domain/models/next_result.dart';
import '../../../domain/models/skip_mode.dart';
import '../../../domain/models/skip_range.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/watch_order_repository.dart';
import '../../../domain/repositories/watch_state_repository.dart';
import '../../../playback/media_remote.dart';
import '../../../playback/playback_controller.dart';
import '../../../playback/playback_rules.dart';
import '../../window_chrome.dart';
import '../controls/player_controls_state.dart';

/// Builds the media remote the session reports to. Injected so the session's
/// tests can hand in [MediaRemote.silent] — the real one registers a method
/// channel handler that has no native side under `flutter test`.
typedef MediaRemoteFactory =
    MediaRemote Function({
      required VoidCallback onPlay,
      required VoidCallback onPause,
      required VoidCallback onTogglePlayPause,
      required VoidCallback onNext,
    });

/// Everything the player DOES with an episode, as a plain object with no
/// widget in it: open at the resume point, mark watched from playback, fire or
/// offer intro/outro skips, run the up-next countdown, advance, and persist
/// progress. `VideoZone` owns one of these and renders what it publishes on
/// [controls]; the theater's other zones never see it.
///
/// Why a class and not the widget's State: every rule in here used to live in
/// the video zone's stream handlers, where the only test was to play a file.
/// The DECISIONS are pure functions in `playback_rules.dart`; this is the
/// SEQUENCING — which event may act when — and it is what had the bugs: a
/// spurious position event auto-skipping over a resume point, two rail taps
/// racing their context loads, settings changed mid-episode never reaching the
/// episode. Each of those is now a test over a stand-in player.
///
/// Two ordering rules hold everything together:
///
/// 1. **A generation per open.** Every open bumps [_generation]; per-episode
///    state is reset SYNCHRONOUSLY at that moment, and every async
///    continuation (the settings/next-episode load, the open itself) checks
///    the generation before touching state. The loser of a race is discarded.
/// 2. **Events arriving before playback has reached its start belong to
///    nobody.** `open()` emits position zero before the engine has sought to
///    the resume point; a per-open [_awaitingStart] latch drops those, so an
///    intro window at 0s cannot fire on the phantom position and seek over the
///    point about to be resumed. During an advance the same applies until the
///    new episode is in place ([_transitioning]).
class PlaybackSession {
  PlaybackSession({
    required this.playback,
    required this.watchState,
    required this.watchOrder,
    required this.settings,
    required Episode episode,
    required VoidCallback onToggleFullscreen,
    this.onEpisodeChanged,
    bool fullscreen = false,
    MediaRemoteFactory remoteFactory = MediaRemote.new,
    this.saveCadence = const Duration(seconds: 1),
  }) : _shown = episode,
       _fullscreen = fullscreen {
    controls = ValueNotifier(
      PlayerControlsState(episode: episode, fullscreen: fullscreen),
    );
    actions = PlayerControlsActions(
      skipIntro: skipIntro,
      skipOutro: skipOutro,
      playNext: () => unawaited(advance()),
      cancelPreRoll: cancelPreRoll,
      // Indirection, not a direct tear-off: the host's callback is read at
      // CALL time, so this bundle can't pin a stale one if the host rebuilds
      // with a different closure.
      toggleFullscreen: () => onToggleFullscreen(),
    );
    // System media-remote (AirPods pinch / media keys / Bluetooth). Commands
    // route to the SAME paths the on-screen controls use — never a parallel
    // play/pause: toggle → Player.playOrPause, next → the one advance path.
    _remote = remoteFactory(
      onPlay: () => unawaited(_guard(playback.player.play(), 'play')),
      onPause: () => unawaited(_guard(playback.player.pause(), 'pause')),
      onTogglePlayPause: () =>
          unawaited(_guard(playback.player.playOrPause(), 'playOrPause')),
      onNext: () => unawaited(advance()),
    );
    // Cmd-Q: the position is committed and AWAITED before the process ends.
    // The 1-second save timer and the `onInactive` save were both races the
    // runner could win; this one it waits for.
    _removeQuitHook = WindowChrome.addQuitHook(persistNow);
  }

  late final VoidCallback _removeQuitHook;

  /// The app-lifetime engine. Consumed, never owned: the session opens on it
  /// and [PlaybackController.stop]s it on the way out, and must NEVER dispose
  /// it.
  final PlaybackController playback;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// App-wide settings (one injected object); read per episode and again on
  /// [reloadContext] when the settings window closes over the player.
  final SettingsRepository settings;

  /// Told when the session advanced on its own, so the host's list can follow.
  final ValueChanged<Episode>? onEpisodeChanged;

  /// How often steady playback commits its position. Short so progress feels
  /// live; the write is skipped when the position has not moved.
  final Duration saveCadence;

  /// How long a paused scrub is left to settle before its position is saved.
  /// Paused position only changes by seeking, and a drag emits many positions
  /// per second — one write for the place the viewer lets go.
  static const Duration pausedSaveDebounce = Duration(milliseconds: 250);

  /// What the control bar renders, in both windowed and fullscreen.
  late final ValueNotifier<PlayerControlsState> controls;
  late final PlayerControlsActions actions;
  late final MediaRemote _remote;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String>? _errorSub;
  Timer? _saveTimer;
  Timer? _pausedSave;
  bool _started = false;
  bool _disposed = false;

  Episode _shown;
  bool _fullscreen;

  /// The episode this session is playing.
  Episode get episode => _shown;

  // ---- per-open state (reset by _resetForEpisode) -----------------------

  int _generation = 0;
  bool _awaitingStart = false;
  bool _transitioning = false;
  Duration _position = Duration.zero;
  Duration _lastPos = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _lastSaved;
  bool _markedWatched = false;
  bool _markAttempted = false;
  Episode? _next;
  bool _preRollCancelled = false;
  bool _preRollShowing = false;
  int _preRollSeconds = 0;
  bool _showSkipIntro = false;
  bool _showSkipOutro = false;
  bool _introSkipped = false;
  bool _outroSkipped = false;
  String? _error;

  // ---- per-context state (loaded from settings) -------------------------

  /// Watched-threshold (time-from-end). Zero disables auto-watched entirely.
  /// The [_thresholdLoaded] gate keeps the seed out of the logic until the
  /// real value has loaded.
  Duration _watchedThreshold = watchedThresholdDefault;
  bool _thresholdLoaded = false;
  bool _autoPlayEnabled = false;
  SkipMode _skipMode = SkipMode.button;

  static bool _sameEpisode(Episode a, Episode b) =>
      a.seriesId == b.seriesId && a.anchoredNumber == b.anchoredNumber;

  /// Open the episode and start listening. Once.
  void start() {
    assert(!_started, 'PlaybackSession.start() called twice');
    _started = true;
    final p = playback.player;
    _posSub = p.stream.position.listen(_onPosition);
    _durSub = p.stream.duration.listen(_onDuration);
    _completedSub = p.stream.completed.listen((done) {
      if (done) unawaited(_onCompleted());
    });
    // Reflect play/pause to the OS immediately, and SAVE on the transition so
    // a pause commits the resume position at once (not only on the timer).
    _playingSub = p.stream.playing.listen((_) {
      persist();
      _pushNowPlaying();
    });
    // The engine's failures, surfaced: a missing file, an unreadable
    // container, a codec libmpv lacks. Before this the frame stayed black and
    // the only trace was in mpv's own log.
    _errorSub = p.stream.error.listen(_onEngineError);
    _saveTimer = Timer.periodic(saveCadence, (_) {
      persist();
      _pushNowPlaying();
    });
    unawaited(_open(_shown));
  }

  /// Host-driven swap (a rail tap). Same episode → nothing.
  void select(Episode episode) {
    if (_sameEpisode(episode, _shown)) return;
    persist();
    unawaited(_open(episode));
  }

  /// The fullscreen flag is the host's; it is relayed so the bar can render
  /// the right icon and pick its config.
  set fullscreen(bool value) {
    if (value == _fullscreen) return;
    _fullscreen = value;
    _publish();
  }

  /// Re-read the settings this episode plays under — skip mode, auto-play,
  /// watched threshold — without re-opening it or re-arming anything. Called
  /// when the settings window closes over the player, so a change made
  /// mid-episode applies to the episode that is playing.
  Future<void> reloadContext() => _loadContext(_shown);

  // ---- opening --------------------------------------------------------

  Future<void> _open(Episode episode) async {
    final gen = _resetForEpisode(episode);
    final startAt = PlaybackController.resumeStartFor(episode);
    _awaitingStart = startAt > Duration.zero;
    _lastPos = startAt;
    _pushNowPlaying(); // new title to the OS now-playing center
    unawaited(_loadContext(episode));
    try {
      await playback.open(episode, startAt: startAt);
    } catch (e, s) {
      if (gen != _generation) return;
      AppLog.error(
        'Playback: could not open ${episode.fileRef}',
        error: e,
        stack: s,
      );
      _setError('$e');
    }
  }

  /// Synchronous: from this line on, every event belongs to [episode].
  int _resetForEpisode(Episode episode) {
    _shown = episode;
    _position = Duration.zero;
    _lastPos = Duration.zero;
    _duration = Duration.zero;
    _lastSaved = null;
    _markedWatched = false;
    _markAttempted = false;
    _next = null;
    _preRollCancelled = false;
    _preRollShowing = false;
    _preRollSeconds = 0;
    _showSkipIntro = false;
    _showSkipOutro = false;
    _introSkipped = false;
    _outroSkipped = false;
    _error = null;
    _awaitingStart = false;
    _resumeOnReveal = false;
    _pausedSave?.cancel();
    _publish();
    return ++_generation;
  }

  Future<void> _loadContext(Episode episode) async {
    final gen = _generation;
    try {
      final (enabled, mode, threshold, result) = await (
        settings.loadAutoPlayNext(),
        settings.loadSkipMode(),
        settings.loadWatchedThreshold(),
        watchOrder.nextEpisode(episode),
      ).wait;
      if (gen != _generation || _disposed) return; // a later open won
      _autoPlayEnabled = enabled;
      _skipMode = mode;
      _watchedThreshold = threshold;
      _thresholdLoaded = true;
      _next = result is NextEpisode ? result.episode : null;
    } catch (e, s) {
      if (gen != _generation || _disposed) return;
      // Degrade to the defaults already in the fields: skips as buttons, no
      // auto-play, threshold unloaded (so nothing is auto-marked).
      AppLog.warn(
        'Playback: episode context failed to load',
        error: e,
        stack: s,
      );
    }
    _publish();
    // Now that the threshold is known, re-check the short-episode case (it may
    // have loaded after the duration arrived).
    _maybeMarkShortEpisode();
  }

  // ---- engine events --------------------------------------------------

  void _onDuration(Duration d) {
    if (_transitioning) return;
    _duration = d;
    // Duration just became known — an episode SHORTER than the threshold is
    // "past threshold" from the start, so mark watched on open.
    _maybeMarkShortEpisode();
    _pushNowPlaying();
  }

  void _onPosition(Duration pos) {
    if (_transitioning) return;
    if (_awaitingStart) {
      // `open()` reports zero before the engine has sought to the resume
      // point. Acting on it would let an intro at 0s auto-seek over the
      // position about to be restored — the resume point would be lost.
      if (pos == Duration.zero) return;
      _awaitingStart = false;
    }
    final playing = playback.player.state.playing;
    final previous = _lastPos;
    _lastPos = pos;
    _position = pos;
    // Only continuous playback may cross the watched-threshold. A seek (paused
    // or a jump while playing) updates the resume position but never marks.
    if (playing &&
        _canAutoWatch &&
        shouldMarkFromPlayback(
          previous: previous,
          position: pos,
          duration: _duration,
          threshold: _watchedThreshold,
          rate: playback.player.state.rate,
        )) {
      _markWatched();
    }
    // A paused position only changes by seeking, so a scrub moves the resume
    // point — after it settles. During playback the timer handles cadence.
    if (!playing) {
      _pausedSave?.cancel();
      _pausedSave = Timer(pausedSaveDebounce, persist);
    }
    _applySkips(pos);
    _updatePreRoll(pos);
  }

  Future<void> _onCompleted() async {
    if (_transitioning) return;
    // "Played to the end" ≠ "crossed the watched mark": these are decoupled.
    // Marking watched obeys the threshold setting (off at 0:00) — reaching the
    // end via playback already crossed it in _onPosition; this is the safety
    // net. Auto-advance below is INDEPENDENT and still runs at 0:00.
    if (_thresholdLoaded && _autoWatchedOn && !_markAttempted) _markWatched();
    // Completion advances only when auto-play is on and the viewer did not
    // cancel the pre-roll — a cancelled countdown means "stop here".
    if (_autoPlayEnabled && _next != null && !_preRollCancelled) {
      await advance();
    }
  }

  void _onEngineError(String message) {
    AppLog.error('mpv: $message');
    if (_transitioning) return;
    _setError(message);
  }

  void _setError(String message) {
    _error = message;
    _publish();
  }

  // ---- watched --------------------------------------------------------

  bool get _autoWatchedOn => _watchedThreshold > Duration.zero;

  /// Whether auto-watched marking can currently apply (setting loaded, not
  /// off, not already attempted for this episode, duration known).
  bool get _canAutoWatch =>
      _thresholdLoaded &&
      _autoWatchedOn &&
      !_markAttempted &&
      _duration > Duration.zero;

  void _maybeMarkShortEpisode() {
    if (!_canAutoWatch) return;
    if (wholeEpisodeWithinThreshold(
      duration: _duration,
      threshold: _watchedThreshold,
    )) {
      _markWatched();
    }
  }

  /// One attempt per episode. The write is the AUTO path, which yields to a
  /// manual "mark unwatched": when it reports that it did not apply, progress
  /// keeps saving — before this, the local latch set regardless and a
  /// re-watch of a manually-unwatched episode froze its resume point at the
  /// threshold for the rest of the episode.
  void _markWatched() {
    _markAttempted = true;
    _markedWatched = true; // optimistic: no progress write while in flight
    final target = _shown;
    final gen = _generation;
    unawaited(
      watchState
          .setWatched(target, watched: true)
          .then((applied) {
            if (gen != _generation) return;
            if (!applied) _markedWatched = false;
          })
          .catchError((Object e, StackTrace s) {
            AppLog.warn('Playback: watched mark failed', error: e, stack: s);
            if (gen == _generation) _markedWatched = false;
          }),
    );
  }

  // ---- skips ------------------------------------------------------------

  void _applySkips(Duration pos) {
    final decision = decideSkips(
      mode: _skipMode,
      episode: _shown,
      position: pos,
      introSkipped: _introSkipped,
      outroSkipped: _outroSkipped,
      preRollShowing: _preRollShowing,
    );
    switch (decision.auto) {
      case AutoSkip.intro:
        _introSkipped = true;
        _seek(_shown.introSkip!.end);
        return;
      case AutoSkip.outro:
        _outroSkipped = true;
        _seekPastOutro(_shown.outroSkip!);
        return;
      case AutoSkip.none:
        break;
    }
    if (decision.showIntroButton != _showSkipIntro ||
        decision.showOutroButton != _showSkipOutro) {
      _showSkipIntro = decision.showIntroButton;
      _showSkipOutro = decision.showOutroButton;
      _publish();
    }
  }

  void skipIntro() {
    final intro = _shown.introSkip;
    if (intro != null) _seek(intro.end);
    _showSkipIntro = false;
    _publish();
  }

  void skipOutro() {
    final outro = _shown.outroSkip;
    if (outro != null) _seekPastOutro(outro);
    _showSkipOutro = false;
    _publish();
  }

  /// Seek to the END of the outro window — staying in the episode so any
  /// post-credits scene plays, and short of the file end so the seek itself
  /// can never complete the episode (see [outroSeekTarget]).
  void _seekPastOutro(SkipRange outro) {
    final target = outroSeekTarget(
      outro: outro,
      duration: _duration,
      position: _position,
    );
    if (target != null) _seek(target);
  }

  void _seek(Duration target) =>
      unawaited(_guard(playback.seekTo(target), 'seek'));

  // ---- up next ----------------------------------------------------------

  void _updatePreRoll(Duration pos) {
    if (!_autoPlayEnabled ||
        _next == null ||
        _preRollCancelled ||
        _duration <= Duration.zero) {
      return;
    }
    final secs = preRollSecondsFor(_duration - pos);
    if (secs == null) {
      if (_preRollShowing) {
        _preRollShowing = false;
        _publish();
      }
      return;
    }
    if (!_preRollShowing || secs != _preRollSeconds) {
      _preRollShowing = true;
      _preRollSeconds = secs;
      _publish();
    }
  }

  /// Pause playback (the host is obscured, or the viewer asked). Idempotent.
  void pause() => unawaited(_guard(playback.player.pause(), 'pause'));

  /// Another page or a dialog now sits over the player: pause, remembering
  /// whether it WAS playing so [resumeIfObscurePaused] can pick it back up.
  /// Audio behind an unrelated screen is never what the viewer meant; a
  /// player that stays paused after Done is not either.
  void pauseForObscured() {
    _resumeOnReveal = playback.player.state.playing;
    pause();
  }

  /// The overlay went away: play again only if [pauseForObscured] paused
  /// something that was playing. A viewer who had paused stays paused.
  void resumeIfObscurePaused() {
    if (!_resumeOnReveal) return;
    _resumeOnReveal = false;
    unawaited(_guard(playback.player.play(), 'play'));
  }

  bool _resumeOnReveal = false;

  void cancelPreRoll() {
    _preRollCancelled = true;
    _preRollShowing = false;
    _publish();
  }

  /// The one advance path. On success it points the session at the new
  /// episode and tells the host (so the episode list follows); at a season
  /// boundary it stops cleanly. Concurrent triggers join the controller's
  /// in-flight advance and cause nothing further.
  Future<void> advance() async {
    if (_transitioning) return;
    // Episode-switch is a graceful departure from the outgoing episode: commit
    // its exact position before opening the next (a no-op once it's watched).
    persist();
    _transitioning = true; // engine events belong to nobody until we reset
    Episode? next;
    try {
      next = await playback.advanceToNext();
    } catch (e, s) {
      AppLog.error('Playback: advance failed', error: e, stack: s);
      _transitioning = false;
      if (!_disposed) _setError('$e');
      return;
    }
    _transitioning = false;
    if (_disposed) return;
    if (next == null) {
      _preRollShowing = false;
      _publish();
      return;
    }
    _resetForEpisode(next);
    _awaitingStart = PlaybackController.resumeStartFor(next) > Duration.zero;
    _pushNowPlaying();
    onEpisodeChanged?.call(next);
    await _loadContext(next);
  }

  // ---- persistence --------------------------------------------------

  /// Commit the resume position. Skipped once the episode is watched, before
  /// playback has a position, and when the position has not moved since the
  /// last write — the timer ticks on while paused, and a paused player has
  /// nothing new to say.
  void persist() => unawaited(persistNow());

  /// [persist], awaitable — the quit hook waits on this one.
  Future<void> persistNow() {
    if (_disposed || _markedWatched) return Future.value();
    if (_duration <= Duration.zero || _position <= Duration.zero) {
      return Future.value();
    }
    if (_lastSaved == _position) return Future.value();
    _lastSaved = _position;
    return _guard(
      watchState.saveProgress(_shown, position: _position, duration: _duration),
      'saveProgress',
    );
  }

  // ---- publishing -------------------------------------------------

  void _publish() {
    if (_disposed) return;
    controls.value = PlayerControlsState(
      episode: _shown,
      skipMode: _skipMode,
      showSkipIntro: _showSkipIntro,
      showSkipOutro: _showSkipOutro,
      upNext: _next,
      preRollShowing: _preRollShowing,
      preRollSeconds: _preRollSeconds,
      fullscreen: _fullscreen,
      errorMessage: _error,
    );
  }

  ({String title, bool playing, int second})? _lastNowPlaying;

  /// Publish the current episode + engine state to the OS now-playing center,
  /// when something it shows has changed — a paused player is not re-sent
  /// every tick.
  void _pushNowPlaying() {
    if (_disposed) return;
    final playing = playback.player.state.playing;
    final snapshot = (
      title: _shown.displayTitle,
      playing: playing,
      second: _position.inSeconds,
    );
    if (snapshot == _lastNowPlaying) return;
    _lastNowPlaying = snapshot;
    unawaited(
      _guard(
        _remote.updateNowPlaying(
          title: snapshot.title,
          duration: _duration,
          position: _position,
          playing: playing,
        ),
        'updateNowPlaying',
      ),
    );
  }

  /// A fire-and-forget engine or repository call that must never become an
  /// unhandled error: it is logged, and playback carries on.
  Future<void> _guard(Future<void> future, String what) =>
      future.catchError((Object e, StackTrace s) {
        AppLog.warn('Playback: $what failed', error: e, stack: s);
      });

  /// Graceful departure (route pop / widget teardown): commit the final
  /// position, release the remote, STOP the engine — never dispose it, the
  /// composition root owns the one dispose.
  Future<void> dispose() async {
    if (_disposed) return;
    // Everything up to the stop is SYNCHRONOUS, so the final save is issued
    // before the caller's frame ends and no event can land in between.
    _saveTimer?.cancel();
    _pausedSave?.cancel();
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_errorSub?.cancel());
    persist();
    _disposed = true;
    _removeQuitHook();
    _remote.dispose(); // relinquish now-playing + stop receiving commands
    controls.dispose();
    await _guard(playback.stop(), 'stop');
  }
}
