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
import '../../../playback/playback_controller.dart';
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
    required this.autoPlayEnabled,
    required this.skipMode,
    this.onEpisodeChanged,
  });

  final Episode episode;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;
  final Future<bool> Function() autoPlayEnabled;
  final Future<SkipMode> Function() skipMode;
  final ValueChanged<Episode>? onEpisodeChanged;

  @override
  State<VideoZone> createState() => _VideoZoneState();
}

class _VideoZoneState extends State<VideoZone> {
  static const double _watchedThreshold = 0.90;
  static const Duration _preRollLead = Duration(seconds: 5);

  late final PlaybackController _playback;
  late final ValueNotifier<PlayerControlsState> _controls;
  late final PlayerControlsActions _actions;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _saveTimer;

  late Episode _shown;
  Duration _position = Duration.zero;
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
    _playback.open(_shown, startAt: _shown.resumePosition);
    _loadEpisodeContext(_shown);
    _durSub = _playback.durationStream.listen((d) => _duration = d);
    _posSub = _playback.positionStream.listen(_onPosition);
    _completedSub = _playback.completedStream.listen((done) {
      if (done) _onCompleted();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
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
    _playback.open(episode, startAt: episode.resumePosition);
    _shown = episode;
    _markedWatched = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _preRollShowing = false;
    _loadEpisodeContext(episode);
  }

  Future<void> _loadEpisodeContext(Episode episode) async {
    final enabled = await widget.autoPlayEnabled();
    final mode = await widget.skipMode();
    final result = await widget.watchOrder.nextEpisode(episode);
    if (!mounted) return;
    _autoPlayEnabled = enabled;
    _skipMode = mode;
    _next = result is NextEpisode ? result.episode : null;
    _preRollCancelled = false;
    _preRollShowing = false;
    _showSkipIntro = false;
    _showSkipOutro = false;
    _introSkipped = false;
    _outroSkipped = false;
    _pushControls();
  }

  void _onPosition(Duration pos) {
    _position = pos;
    final total = _duration.inMilliseconds;
    if (!_markedWatched &&
        total > 0 &&
        pos.inMilliseconds >= total * _watchedThreshold) {
      _markedWatched = true;
      widget.watchState.setWatched(_shown, watched: true);
    }

    _applySkips(pos);

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
    if (!_markedWatched) {
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
    _preRollShowing = false;
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
    _persist();
    _controls.dispose();
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A true-black "stage" so letterboxing reads as theater, not a gap. The
    // control bar is rendered by media_kit over the texture via `controls:`,
    // so it overlays the video here AND in the fullscreen route automatically.
    return ColoredBox(
      color: const Color(0xFF0A0A0B),
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
