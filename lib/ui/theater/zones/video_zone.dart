import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/models/next_result.dart';
import '../../../domain/models/skip_mode.dart';
import '../../../domain/models/skip_range.dart';
import '../../../domain/repositories/watch_order_repository.dart';
import '../../../domain/repositories/watch_state_repository.dart';
import '../../../playback/media_remote.dart';
import '../../../playback/playback_controller.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../theme/xp_tokens.dart';
import '../controls/player_control_bar.dart';
import '../controls/player_controls_state.dart';

/// The VIDEO zone: the embedded libmpv (media_kit) playback frame, now driven by
/// our OWN custom control bar ([PlayerControls]) instead of media_kit's default
/// controls. The same bar renders in windowed mode (here) and in media_kit's
/// fullscreen route (it reuses this `controls` builder + the same controller),
/// so the two modes can't drift and the skip affordances show in both.
///
/// Engine state (position/playing/volume/tracks) the bar reads straight from the
/// player streams. The DOMAIN bits the streams don't carry — current episode,
/// live skip affordances, the up-next pre-roll — this zone computes and publishes
/// to a shared `ValueNotifier<PlayerControlsState>` that the bar listens to in
/// BOTH modes. All the playback behavior (resume, watched threshold, skip
/// detection, auto-advance, persistence) lives here, unchanged.
///
/// Swap-in-place: when [episode] changes (list tap, or auto-advance) it re-opens
/// in the same frame on the same controller — no navigation, no duplicate player.
class VideoZone extends StatefulWidget {
  const VideoZone({
    super.key,
    required this.episode,
    required this.watchState,
    required this.watchOrder,
    required this.settings,
    this.onEpisodeChanged,
  });

  final Episode episode;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// App-wide settings (one injected object); this zone reads auto-play, skip
  /// mode, and the watched-threshold from it per episode.
  final SettingsRepository settings;

  final ValueChanged<Episode>? onEpisodeChanged;

  @override
  State<VideoZone> createState() => _VideoZoneState();
}

class _VideoZoneState extends State<VideoZone> {
  static const Duration _preRollLead = Duration(seconds: 5);

  /// Watched-threshold (time-from-end) loaded from the setting per episode. An
  /// episode is auto-marked watched once the time REMAINING drops to/below this.
  /// Zero disables auto-watched entirely (the master off-switch). Seeded from
  /// the default; the [_thresholdLoaded] gate keeps the seed out of the logic
  /// until the real value has loaded (avoids acting on a stale seed).
  Duration _watchedThreshold = watchedThresholdDefault;
  bool _thresholdLoaded = false;
  bool get _autoWatchedOn => _watchedThreshold > Duration.zero;

  late final PlaybackController _playback;
  late final ValueNotifier<PlayerControlsState> _controls;
  late final PlayerControlsActions _actions;
  late final MediaRemote _remote;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _saveTimer;

  /// Commits progress when the APP itself is leaving (window loses focus /
  /// hidden / quit) — the graceful-exit save for departures that don't dispose
  /// this widget (a route pop does; a Cmd-Q / minimise doesn't). Best-effort on
  /// a hard quit; the periodic timer remains the crash/force-quit safety net.
  late final AppLifecycleListener _lifecycle;

  late Episode _shown;
  Duration _position = Duration.zero;

  /// The previous position observed, to tell CONTINUOUS playback advance from a
  /// SEEK jump — only the former may cross the watched-threshold.
  Duration _lastPos = Duration.zero;
  Duration _duration = Duration.zero;
  bool _markedWatched = false;

  Episode? _next;
  bool _autoPlayEnabled = false;
  bool _preRollCancelled = false;
  bool _preRollShowing = false;
  int _preRollSeconds = 0;

  SkipMode _skipMode = SkipMode.button;
  bool _showSkipIntro = false;
  bool _showSkipOutro = false;
  bool _introSkipped = false;
  bool _outroSkipped = false;

  static bool _sameEpisode(Episode a, Episode b) =>
      a.seriesAnilistId == b.seriesAnilistId &&
      a.anchoredNumber == b.anchoredNumber;

  /// Publish current domain state to the shared notifier (engine state goes via
  /// player streams, not here). Replaces the old per-widget setState — so the
  /// windowed AND fullscreen bars both see every change.
  void _pushControls() {
    _controls.value = PlayerControlsState(
      episode: _shown,
      skipMode: _skipMode,
      showSkipIntro: _showSkipIntro,
      showSkipOutro: _showSkipOutro,
      upNext: _next,
      preRollShowing: _preRollShowing,
      preRollSeconds: _preRollSeconds,
    );
  }

  @override
  void initState() {
    super.initState();
    _shown = widget.episode;
    _playback = PlaybackController(resolver: widget.watchOrder);
    _controls = ValueNotifier(PlayerControlsState(episode: _shown));
    _actions = PlayerControlsActions(
      skipIntro: _skipIntro,
      skipOutro: _skipOutro,
      playNext: _goToNext,
      cancelPreRoll: _cancelPreRoll,
    );
    // System media-remote (AirPods pinch / media keys / Bluetooth). Commands
    // route to the SAME paths the on-screen controls use — never a parallel
    // play/pause: toggle → Player.playOrPause, next → the one advance path.
    _remote = MediaRemote(
      onPlay: _playback.player.play,
      onPause: _playback.player.pause,
      onTogglePlayPause: _playback.player.playOrPause,
      onNext: _goToNext,
    );
    _playback.open(_shown, startAt: PlaybackController.resumeStartFor(_shown));
    _loadEpisodeContext(_shown);
    _durSub = _playback.durationStream.listen((d) {
      _duration = d;
      // Duration just became known — an episode SHORTER than the threshold is
      // "past threshold" from the start, so mark watched on open.
      _maybeMarkShortEpisode();
      _pushNowPlaying();
    });
    _posSub = _playback.positionStream.listen(_onPosition);
    _completedSub = _playback.completedStream.listen((done) {
      if (done) _onCompleted();
    });
    // Reflect play/pause to the OS immediately, and SAVE on the transition so a
    // pause commits the resume position at once (not only on the timer tick).
    _playingSub = _playback.player.stream.playing.listen((_) {
      _persist();
      _pushNowPlaying();
    });
    // A short save cadence so progress feels live (was 5s — laggy). Event-saves
    // (pause above, paused-seek in _onPosition) cover the meaningful moments;
    // this 1s tick covers steady playback WITHOUT a per-frame DB write. Doubles
    // as the OS now-playing refresh.
    _saveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _persist();
      _pushNowPlaying();
    });
    // Save the moment the app is backgrounded / hidden / about to quit —
    // `inactive` is the earliest such signal on every platform. In-app route
    // pushes don't change the app lifecycle, so this fires only on a real
    // departure from the app, not on navigation within it.
    _lifecycle = AppLifecycleListener(onInactive: _persist);
  }

  /// Publish the current episode + engine state to the OS now-playing center.
  /// The title reuses the same fallback the info zone shows.
  void _pushNowPlaying() {
    _remote.updateNowPlaying(
      title: _shown.title ?? 'Episode ${_shown.number}',
      duration: _duration,
      position: _position,
      playing: _playback.player.state.playing,
    );
  }

  @override
  void didUpdateWidget(VideoZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameEpisode(widget.episode, _shown)) {
      _switchTo(widget.episode);
    }
  }

  /// Host-driven swap (list tap). Save the outgoing episode, then open the new
  /// one in place and reset per-episode state.
  void _switchTo(Episode episode) {
    _persist();
    _playback.open(
      episode,
      startAt: PlaybackController.resumeStartFor(episode),
    );
    _shown = episode;
    _markedWatched = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastPos = Duration.zero;
    _preRollShowing = false;
    _loadEpisodeContext(episode);
    _pushNowPlaying(); // new title to the OS now-playing center
  }

  Future<void> _loadEpisodeContext(Episode episode) async {
    final enabled = await widget.settings.loadAutoPlayNext();
    final mode = await widget.settings.loadSkipMode();
    final result = await widget.watchOrder.nextEpisode(episode);
    if (!mounted) return;
    final threshold = await widget.settings.loadWatchedThreshold();
    if (!mounted) return;
    _autoPlayEnabled = enabled;
    _skipMode = mode;
    _watchedThreshold = threshold;
    _thresholdLoaded = true;
    _next = result is NextEpisode ? result.episode : null;
    _preRollCancelled = false;
    _preRollShowing = false;
    _showSkipIntro = false;
    _showSkipOutro = false;
    _introSkipped = false;
    _outroSkipped = false;
    _pushControls();
    // Now that the threshold is known, re-check the short-episode case (it may
    // have loaded after the duration arrived).
    _maybeMarkShortEpisode();
  }

  /// Whether auto-watched marking can currently apply (setting loaded, not off,
  /// not already marked, duration known).
  bool get _canAutoWatch =>
      _thresholdLoaded &&
      _autoWatchedOn &&
      !_markedWatched &&
      _duration.inMilliseconds > 0;

  void _markWatched() {
    _markedWatched = true;
    widget.watchState.setWatched(_shown, watched: true);
  }

  /// "Episode shorter than the threshold" → the whole episode is inside the
  /// threshold window, so it's watched the moment it opens (position-independent,
  /// never a seek). Called when the duration/threshold become known.
  void _maybeMarkShortEpisode() {
    if (!_canAutoWatch) return;
    if (_duration.inMilliseconds <= _watchedThreshold.inMilliseconds) {
      _markWatched();
    }
  }

  /// Watched-mark from CONTINUOUS PLAYBACK reaching the threshold — never from a
  /// seek. [deltaMs] is the advance since the last position: a small forward
  /// step is natural playback; a jump (or backward) is a seek and must NOT mark
  /// (so scrubbing near the end can't accidentally complete the episode).
  void _maybeMarkFromPlayback(int deltaMs) {
    if (!_canAutoWatch) return;
    if (deltaMs < 0 || deltaMs > 2000) return; // a seek jump, not playback
    final remaining = _duration.inMilliseconds - _position.inMilliseconds;
    if (remaining <= _watchedThreshold.inMilliseconds) _markWatched();
  }

  void _onPosition(Duration pos) {
    final playing = _playback.player.state.playing;
    final deltaMs = pos.inMilliseconds - _lastPos.inMilliseconds;
    _lastPos = pos;
    _position = pos;
    // Only continuous playback may cross the watched-threshold. A seek (paused
    // or a jump while playing) updates the resume position but never marks.
    if (playing) _maybeMarkFromPlayback(deltaMs);
    // Save immediately on a paused seek/scrub — paused position only changes via
    // a seek, so this "seeking moves the resume point" even without playing.
    // During playback the 1s timer handles cadence (no per-frame DB write).
    if (!playing) _persist();

    _applySkips(pos);

    final total = _duration.inMilliseconds;
    if (_autoPlayEnabled && _next != null && !_preRollCancelled && total > 0) {
      final remaining = _duration - pos;
      if (remaining > Duration.zero && remaining <= _preRollLead) {
        final secs = math.min(
          _preRollLead.inSeconds,
          (remaining.inMilliseconds + 999) ~/ 1000,
        );
        if (!_preRollShowing || secs != _preRollSeconds) {
          _preRollShowing = true;
          _preRollSeconds = secs;
          _pushControls();
        }
      } else if (_preRollShowing) {
        _preRollShowing = false;
        _pushControls();
      }
    }
  }

  /// Intro/outro per [_skipMode], driven by the cached windows on [_shown]
  /// (offline). Intro skip seeks to the window end; outro skip seeks past the
  /// credits WITHIN the episode (never advances).
  void _applySkips(Duration pos) {
    if (_skipMode == SkipMode.off) {
      if (_showSkipIntro || _showSkipOutro) {
        _showSkipIntro = false;
        _showSkipOutro = false;
        _pushControls();
      }
      return;
    }
    final intro = _shown.introSkip;
    final outro = _shown.outroSkip;
    final inIntro = intro != null && intro.contains(pos);
    final inOutro = outro != null && outro.contains(pos);

    if (_skipMode == SkipMode.auto) {
      if (inIntro && !_introSkipped) {
        _introSkipped = true;
        _playback.seekTo(intro.end);
      } else if (inOutro && !_outroSkipped) {
        _outroSkipped = true;
        _seekPastOutro(outro);
      }
      return;
    }

    // Button mode: toggle the affordances. Hide the outro button while the
    // up-next pre-roll occupies the bar.
    final showIntro = inIntro;
    final showOutro = inOutro && !_preRollShowing;
    if (showIntro != _showSkipIntro || showOutro != _showSkipOutro) {
      _showSkipIntro = showIntro;
      _showSkipOutro = showOutro;
      _pushControls();
    }
  }

  void _skipIntro() {
    final intro = _shown.introSkip;
    if (intro != null) _playback.seekTo(intro.end);
    _showSkipIntro = false;
    _pushControls();
  }

  void _skipOutro() {
    final outro = _shown.outroSkip;
    if (outro != null) _seekPastOutro(outro);
    _showSkipOutro = false;
    _pushControls();
  }

  /// Seek to the END of the outro window — staying in the episode so any
  /// post-credits scene plays. Clamp to the file end if the window overhangs.
  void _seekPastOutro(SkipRange outro) {
    final target = (_duration > Duration.zero && outro.end > _duration)
        ? _duration
        : outro.end;
    _playback.seekTo(target);
  }

  void _persist() {
    if (_markedWatched) return;
    if (_duration.inMilliseconds <= 0 || _position.inMilliseconds <= 0) return;
    widget.watchState.saveProgress(
      _shown,
      position: _position,
      duration: _duration,
    );
  }

  Future<void> _onCompleted() async {
    // "Played to the end" ≠ "crossed the watched mark": these are decoupled.
    // Marking watched obeys the threshold setting (off at 0:00) — reaching the
    // end via playback already crossed it in _maybeMarkFromPlayback; this is the
    // safety net. Auto-advance below is INDEPENDENT and still runs at 0:00.
    if (_autoWatchedOn && !_markedWatched) {
      _markedWatched = true;
      await widget.watchState.setWatched(_shown, watched: true);
    }
    if (_autoPlayEnabled && _next != null && !_preRollCancelled) {
      await _goToNext();
    }
  }

  /// The one advance path. On success it updates the frame + tells the host (so
  /// the episode list follows); at a season boundary it stops cleanly.
  Future<void> _goToNext() async {
    // Episode-switch is a graceful departure from the outgoing episode: commit
    // its exact position before opening the next (a no-op once it's watched,
    // e.g. an end-of-episode auto-advance that already cleared resume).
    _persist();
    final next = await _playback.advanceToNext();
    if (!mounted) return;
    if (next == null) {
      _preRollShowing = false;
      _pushControls();
      return;
    }
    _shown = next;
    _markedWatched = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastPos = Duration.zero;
    _preRollShowing = false;
    _pushNowPlaying(); // new title to the OS now-playing center
    await _loadEpisodeContext(next);
    widget.onEpisodeChanged?.call(next);
  }

  void _cancelPreRoll() {
    _preRollCancelled = true;
    _preRollShowing = false;
    _pushControls();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
    _lifecycle.dispose();
    // Graceful departure (route pop / page-change / widget teardown): commit the
    // exact final position now. Complements the periodic save (the safety net).
    _persist();
    _remote.dispose(); // relinquish now-playing + stop receiving commands
    _controls.dispose();
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A true-black VFD "stage" (Xp.well) so letterboxing reads as an unlit
    // display field, not a gap. The control bar is rendered by media_kit over
    // the texture via `controls:`, so it overlays the video here AND in the
    // fullscreen route automatically.
    return ColoredBox(
      color: Xp.well,
      child: Video(
        controller: _playback.controller,
        controls: (_) => PlayerControls(
          player: _playback.player,
          state: _controls,
          actions: _actions,
        ),
      ),
    );
  }
}
