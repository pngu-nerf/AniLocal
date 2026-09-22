import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../diagnostics/app_log.dart';
import '../../../domain/format_duration.dart';
import '../../../domain/models/episode.dart';
import '../../../domain/models/episode_source.dart';
import '../../../domain/models/next_result.dart';
import '../../../domain/models/skip_mode.dart';
import '../../../domain/models/skip_range.dart';
import '../../../domain/paths.dart' show basenameOf;
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/source_selection_repository.dart';
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
    this.sourceSelection,
    this.refetchEpisode,
    bool fullscreen = false,
    MediaRemoteFactory remoteFactory = MediaRemote.new,
    this.saveCadence = const Duration(seconds: 1),
    Future<bool> Function(String path)? fileExists,
  }) : _shown = episode,
       _fullscreen = fullscreen,
       _fileExists = fileExists ?? _fileStillThere {
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
      selectSource: sourceSelection == null || refetchEpisode == null
          ? null
          : (source) => unawaited(switchSource(source)),
      retry: () => unawaited(retry()),
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

  /// Per-episode source pins, for [switchSource]. Optional: a host without
  /// it gets no Copy section in the bar.
  final SourceSelectionRepository? sourceSelection;

  /// Re-read an episode from the library after a pin changed, so its
  /// `fileRef` reflects the new choice. Null when the show has gone.
  final Future<Episode?> Function(Episode episode)? refetchEpisode;

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
      _checkStall();
    });
    unawaited(_open(_shown));
  }

  // ---- the stall watchdog ----------------------------------------------

  /// Whether the file at a path can still be seen. Injected so tests run
  /// under fakeAsync without touching the disk; bounded, because a wedged
  /// mount can hang an `exists()` for as long as the kernel takes to give up,
  /// and "did not answer" is the same news as "gone".
  final Future<bool> Function(String path) _fileExists;

  static Future<bool> _fileStillThere(String path) => File(
    path,
  ).exists().timeout(const Duration(seconds: 2), onTimeout: () => false);

  Duration _lastTickPos = Duration.zero;
  Duration _stalledFor = Duration.zero;
  bool _probing = false;

  /// The third signal of a dead stream. mpv reports a failed OPEN on its
  /// error stream and a truncated file as a completion far from the end; a
  /// volume that vanishes MID-READ produces neither — the position stops and
  /// the frame freezes with pause still false. So: while the engine says it
  /// is playing and the position has not moved for `kStallTolerance`, ask
  /// whether the file is still there. Gone → a playback loss (the fall-through
  /// or the error, at the position it stopped). Present → buffering; wait
  /// another tolerance and ask again.
  void _checkStall() {
    if (_disposed || _transitioning || _probing) return;
    final started = !_awaitingStart && _position > Duration.zero;
    if (!started || _error != null || !playback.player.state.playing) {
      _stalledFor = Duration.zero;
      _lastTickPos = _position;
      return;
    }
    if (_position != _lastTickPos) {
      _lastTickPos = _position;
      _stalledFor = Duration.zero;
      return;
    }
    _stalledFor += saveCadence;
    if (_stalledFor < kStallTolerance) return;
    _stalledFor = Duration.zero; // re-armed: a present file is probed again
    _probing = true;
    final gen = _generation;
    final path = _shown.fileRef;
    unawaited(
      _guard(() async {
        final present = await _fileExists(path);
        _probing = false;
        if (_disposed || gen != _generation || present) return;
        final at = _position;
        _onOpenFailed(
          'Playback stopped at ${formatDuration(at)} — the file is no longer '
          'readable. Was the drive disconnected?',
        );
      }(), 'stall probe'),
    );
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

  /// Play the same episode from another copy — [source] — or, with null,
  /// from the folder-priority default again. The pin is written, the
  /// episode re-read (its `fileRef` now reflects the choice), and playback
  /// re-opened at the CURRENT position: a copy switch is not a re-watch, so
  /// the watched-episode rule that would start from zero does not apply.
  Future<void> switchSource(EpisodeSource? source) => _guard(() async {
    final selection = sourceSelection;
    final refetch = refetchEpisode;
    if (selection == null || refetch == null || _disposed) return;
    final current = _shown;
    final alreadyPinned = source != null && current.isPinned(source);
    final alreadyAutomatic =
        source == null && current.pinnedSourceFolder == null;
    if (alreadyPinned || alreadyAutomatic) return;
    // The place to keep: the live position, or — after a FAILED open, which
    // leaves it at zero — the position that open was asked to start from. A
    // good source picked after a corrupted one used to start over.
    final at = _position > Duration.zero ? _position : _lastPos;
    await persistNow();
    if (source == null) {
      await selection.clearSource(current);
    } else {
      await selection.selectSource(current, source);
    }
    final fresh = await refetch(current) ?? current;
    if (_disposed) return;
    _failoverTried.clear(); // the user chose; every copy is fair again
    onEpisodeChanged?.call(fresh);
    if (fresh.fileRef == current.fileRef) {
      // The default was this file all along: nothing to re-open.
      _shown = fresh;
      _publish();
      return;
    }
    await _open(fresh, startAt: at);
  }(), 'switchSource');

  /// Open the episode again where it was — the error notice's Retry. A
  /// replugged drive used to need a click off the episode and back. Re-reads
  /// the episode when the host allows, so the Automatic default is whatever
  /// is reachable NOW (the replugged drive's copy again), with every copy
  /// fair again, at the last position the engine reported. The host is told,
  /// so the rail and the video agree.
  Future<void> retry() => _guard(() async {
    if (_disposed) return;
    _failoverTried.clear();
    final at = _lastPos;
    final target = await refetchEpisode?.call(_origin) ?? _origin;
    if (_disposed) return;
    onEpisodeChanged?.call(target);
    await _open(target, startAt: at > Duration.zero ? at : null);
  }(), 'retry');

  /// The copy that could not be opened: try the next one, or say so.
  ///
  /// Automatic means "play this episode", not "play this file": an unplugged
  /// drive or a 0-byte download on the default copy used to be a dead end
  /// until the user pinned another copy by hand. A PINNED episode is left
  /// alone — the pin is the user's — and shows the error with Retry. Each
  /// copy is tried once per episode, so two dead copies cannot ping-pong.
  void _onOpenFailed(String message) {
    if (_disposed || _transitioning) return;
    final current = _shown;
    _failoverTried.add(current.fileRef);
    if (current.pinnedSourceFolder == null) {
      for (final s in current.sources) {
        if (_failoverTried.contains(s.fileRef)) continue;
        _showNotice(
          'Playing the source in ${basenameOf(s.folderPath)} instead',
        );
        unawaited(
          _open(current.playingFrom(s), startAt: _lastPos, failover: true),
        );
        return;
      }
    }
    _setError(message);
  }

  /// Copies already tried for the CURRENT episode identity.
  final Set<String> _failoverTried = {};

  /// The episode as the host gave it — what Retry re-opens (a fall-through
  /// replaces [_shown] with the same episode on another copy).
  late Episode _origin = _shown;

  String? _notice;
  Timer? _noticeTimer;
  void _showNotice(String text) {
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      _notice = null;
      _publish();
    });
    _publish();
  }

  Future<void> _open(
    Episode episode, {
    Duration? startAt,
    bool failover = false,
  }) async {
    if (!failover) _origin = episode;
    final gen = _resetForEpisode(episode);
    startAt ??= PlaybackController.resumeStartFor(episode);
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
    if (!_sameEpisode(episode, _shown)) {
      // A different episode: the copies tried and the notice were about the
      // last one. Within one episode (a fall-through) they carry over.
      _failoverTried.clear();
      _noticeTimer?.cancel();
      _notice = null;
    }
    _shown = episode;
    _position = Duration.zero;
    _lastPos = Duration.zero;
    _progressStreak = 0;
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
    // PLAYBACK after an error means the engine recovered (a transient decoder
    // line, a network hiccup): the notice was about a moment that has passed.
    // Playback, not a position report: a seek on a dead stream reports its
    // target, and a stuck stream re-reports the same value, and either used
    // to wipe the notice the stall watchdog had just raised — so it flickered
    // and came back six seconds later. Two consecutive small forward steps.
    if (_error != null) {
      final step = pos - previous;
      final looksLikePlayback =
          step > Duration.zero && step <= kPlaybackStepMax;
      _progressStreak = looksLikePlayback ? _progressStreak + 1 : 0;
      if (_progressStreak >= 2) {
        _error = null;
        _progressStreak = 0;
        _publish();
      }
    }
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
    // "Completed" from a file that never PLAYED — a 0-byte download, a drive
    // that is gone — is a failed open, not an ending. It used to advance:
    // episode 2 failed the same way, then 3, and the viewer landed three
    // episodes on with nothing having played. Evidence of playback is a
    // duration and a position past the phantom zero.
    if (_error != null ||
        _awaitingStart ||
        _duration <= Duration.zero ||
        _position <= Duration.zero) {
      _onOpenFailed('The file ended before it started playing.');
      return;
    }
    // "Completed" far from the END is a stream that died — a drive pulled
    // mid-play makes mpv report EOF the moment its buffer runs dry. A real
    // ending has the position at the duration (the outro seek lands 750 ms
    // short; a VBR estimate can be a second off). It used to advance, so the
    // viewer landed on episode 2 — which then failed on the same drive.
    if (_duration - _position > kCompletionTolerance) {
      _onOpenFailed(
        'Playback stopped at ${_position.inSeconds}s of '
        '${_duration.inSeconds}s — the file could not be read further.',
      );
      return;
    }
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
    // Nothing has played yet: the OPEN failed. Otherwise it is an error mid-
    // play, shown until the engine reports progress again.
    if (_position <= Duration.zero) {
      _onOpenFailed(message);
    } else {
      _setError(message);
    }
  }

  void _setError(String message) {
    _error = message;
    _progressStreak = 0;
    _publish();
  }

  /// Consecutive playback-sized forward steps seen while an error is up.
  int _progressStreak = 0;

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
    // Retry re-opens the episode that is CURRENT; an advance makes this one
    // current as surely as an open does.
    _origin = next;
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
      notice: _notice,
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
    _noticeTimer?.cancel();
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
