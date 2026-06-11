import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';
import '../domain/models/next_result.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import '../playback/playback_controller.dart';

/// Plays one episode embedded with libmpv (media_kit) — styled ASS subtitles,
/// seeking, no external window. Resumes from the saved position, saves progress
/// as it plays, and marks watched past a threshold.
///
/// Auto-play next (when enabled): a cancelable "Up next" countdown is a
/// PRE-roll — it appears during the final seconds of the episode and, if left
/// uncancelled, advances the instant playback ends (no play-to-black-then-wait).
/// The advance itself goes through [PlaybackController.advanceToNext], the one
/// entry point shared with future triggers (e.g. seek-past-end). "Next" is the
/// relations-free within-season resolver; at a season boundary it stops cleanly.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.episode,
    required this.watchState,
    required this.watchOrder,
    required this.autoPlayEnabled,
  });

  final Episode episode;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// Reads the current "auto-play next" setting (so toggling it takes effect
  /// without restarting the player). Read per episode.
  final Future<bool> Function() autoPlayEnabled;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Count an episode "watched" at 90%: enough to skip the ED/next-episode
  // preview and still have it count.
  static const double _watchedThreshold = 0.90;
  // The pre-roll countdown overlaps this much of the episode's tail.
  static const Duration _preRollLead = Duration(seconds: 5);

  late final PlaybackController _playback;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _saveTimer;

  late Episode _shown; // the episode currently playing (mirrors controller)
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _markedWatched = false;

  // Per-episode auto-play state.
  Episode? _next; // resolved next for the overlay (null = season boundary)
  bool _autoPlayEnabled = false; // the persisted setting, loaded per episode
  bool _preRollCancelled = false; // user dismissed the countdown this episode
  bool _preRollShowing = false;
  int _preRollSeconds = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.episode;
    _playback = PlaybackController(resolver: widget.watchOrder);
    _playback.open(_shown, startAt: _shown.resumePosition);
    _loadEpisodeContext(_shown);
    _durSub = _playback.durationStream.listen((d) => _duration = d);
    _posSub = _playback.positionStream.listen(_onPosition);
    _completedSub = _playback.completedStream.listen((done) {
      if (done) _onCompleted();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
  }

  /// Reset per-episode state and (re)load the setting + the resolved next.
  Future<void> _loadEpisodeContext(Episode episode) async {
    final enabled = await widget.autoPlayEnabled();
    final result = await widget.watchOrder.nextEpisode(episode);
    if (!mounted) return;
    setState(() {
      _autoPlayEnabled = enabled;
      _next = result is NextEpisode ? result.episode : null;
      _preRollCancelled = false;
      _preRollShowing = false;
    });
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

    // PRE-roll: surface the countdown during the final [_preRollLead] seconds,
    // counting down in step with playback. (Not a post-roll — it overlaps the
    // tail so the advance at end is instant.)
    if (_autoPlayEnabled && _next != null && !_preRollCancelled && total > 0) {
      final remaining = _duration - pos;
      if (remaining > Duration.zero && remaining <= _preRollLead) {
        final secs = math.min(_preRollLead.inSeconds, remaining.inSeconds + 1);
        if (!_preRollShowing || secs != _preRollSeconds) {
          setState(() {
            _preRollShowing = true;
            _preRollSeconds = secs;
          });
        }
      } else if (_preRollShowing) {
        setState(() => _preRollShowing = false);
      }
    }
  }

  void _persist() {
    if (_markedWatched) return; // already finished; resume was cleared
    if (_duration.inMilliseconds <= 0 || _position.inMilliseconds <= 0) return;
    widget.watchState.saveProgress(
      _shown,
      position: _position,
      duration: _duration,
    );
  }

  /// Episode finished: mark watched, then advance immediately if the pre-roll
  /// is live (enabled, has a next, not cancelled). Otherwise stop cleanly.
  Future<void> _onCompleted() async {
    if (!_markedWatched) {
      _markedWatched = true;
      await widget.watchState.setWatched(_shown, watched: true);
    }
    if (_autoPlayEnabled && _next != null && !_preRollCancelled) {
      await _goToNext();
    }
  }

  /// The player-side wrapper over the one advance entry point. Both triggers —
  /// the pre-roll reaching the end and "Play now" — go through here (and a
  /// future seek-past-end will too).
  Future<void> _goToNext() async {
    final next = await _playback.advanceToNext();
    if (!mounted) return;
    if (next == null) {
      setState(() => _preRollShowing = false); // season boundary -> stop
      return;
    }
    setState(() {
      _shown = next;
      _markedWatched = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _preRollShowing = false;
    });
    await _loadEpisodeContext(next);
  }

  void _cancelPreRoll() {
    setState(() {
      _preRollCancelled = true;
      _preRollShowing = false;
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completedSub?.cancel();
    _persist(); // best-effort final save (fire-and-forget)
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_shown.title ?? 'Episode ${_shown.number}')),
      body: Stack(
        children: [
          Positioned.fill(child: Video(controller: _playback.controller)),
          if (_preRollShowing && _next != null)
            Positioned(
              right: 16,
              bottom: 56,
              child: _UpNextCard(
                next: _next!,
                seconds: _preRollSeconds,
                onCancel: _cancelPreRoll,
                onPlayNow: _goToNext,
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating, cancelable "Up next" pre-roll card shown over the final seconds.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.next,
    required this.seconds,
    required this.onCancel,
    required this.onPlayNow,
  });

  final Episode next;
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Up next',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              next.title ?? 'Episode ${next.number}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Playing in $seconds…',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onPlayNow,
                  child: const Text('Play now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
