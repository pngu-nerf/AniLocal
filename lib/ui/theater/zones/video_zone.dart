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

/// The VIDEO zone: the embedded libmpv (media_kit) playback frame — styled ASS
/// subtitles, seeking, no external window — with the skip affordances, skip
/// timeline strip, and the auto-play "Up next" pre-roll. It resumes from the
/// saved position, saves progress as it plays, and marks watched past a
/// threshold.
///
/// Position-agnostic: it FILLS whatever box the layout hands it (a `Stack`
/// with `Positioned.fill` video). It holds no width/position opinion — the
/// theater layout decides where it sits and how large it is.
///
/// Swap-in-place: when [episode] changes (the user picked another episode in
/// the list, or auto-play advanced), it re-opens that episode in the SAME
/// frame — no navigation, same controller. When it auto-advances itself, it
/// reports the new episode via [onEpisodeChanged] so the surrounding screen
/// (e.g. the episode list's "now playing" mark) can follow along.
///
/// Auto-play next (when enabled) is a PRE-roll countdown: it appears during the
/// final seconds and advances the instant playback ends. Advancing always goes
/// through [PlaybackController.advanceToNext], the one shared entry point.
/// "Next" is the within-season resolver; at a season boundary it stops cleanly.
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

  /// The episode to play. Changing it re-opens that episode in place.
  final Episode episode;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// Reads the current "auto-play next" setting (so toggling it takes effect
  /// without restarting the player). Read per episode.
  final Future<bool> Function() autoPlayEnabled;

  /// Reads the current skip mode (off / button / auto). Read per episode.
  final Future<SkipMode> Function() skipMode;

  /// Called when the zone advances itself (auto-play) to a new episode, so the
  /// host can keep its own "current episode" in sync. NOT called when the host
  /// drives the change via [episode].
  final ValueChanged<Episode>? onEpisodeChanged;

  @override
  State<VideoZone> createState() => _VideoZoneState();
}

class _VideoZoneState extends State<VideoZone> {
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

  // Per-episode skip state (intro/outro windows come from _shown).
  SkipMode _skipMode = SkipMode.button;
  bool _showSkipIntro = false;
  bool _showSkipOutro = false;
  bool _introSkipped = false; // auto-skip fires once per window
  bool _outroSkipped = false;

  /// Episode IDENTITY (entry + anchored position) — the swap trigger compares
  /// on this, not the whole object, so a resume-position delta doesn't re-open.
  static bool _sameEpisode(Episode a, Episode b) =>
      a.seriesAnilistId == b.seriesAnilistId &&
      a.anchoredNumber == b.anchoredNumber;

  @override
  void initState() {
    super.initState();
    _shown = widget.episode;
    _playback = PlaybackController(resolver: widget.watchOrder);
    _playback.open(_shown, startAt: _shown.resumePosition);
    _loadEpisodeContext(_shown);
    // setState on duration so the skip-markers bar can lay out once it's known.
    _durSub = _playback.durationStream.listen((d) {
      if (mounted && d != _duration) setState(() => _duration = d);
    });
    _posSub = _playback.positionStream.listen(_onPosition);
    _completedSub = _playback.completedStream.listen((done) {
      if (done) _onCompleted();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
  }

  @override
  void didUpdateWidget(VideoZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host asked for a different episode (list tap). Swap in place. (When
    // WE advanced, the host echoes the same episode back via [episode] — same
    // identity as _shown — so this is a no-op and we don't re-open.)
    if (!_sameEpisode(widget.episode, _shown)) {
      _switchTo(widget.episode);
    }
  }

  /// Open [episode] in the existing frame and reset per-episode state. Used for
  /// host-driven swaps; the auto-advance path uses [_goToNext] instead (which
  /// opens via the resolver).
  void _switchTo(Episode episode) {
    _persist(); // save the outgoing episode's progress before leaving it
    _playback.open(episode, startAt: episode.resumePosition);
    setState(() {
      _shown = episode;
      _markedWatched = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _preRollShowing = false;
    });
    _loadEpisodeContext(episode);
  }

  /// Reset per-episode state and (re)load the setting + the resolved next.
  Future<void> _loadEpisodeContext(Episode episode) async {
    final enabled = await widget.autoPlayEnabled();
    final mode = await widget.skipMode();
    final result = await widget.watchOrder.nextEpisode(episode);
    if (!mounted) return;
    setState(() {
      _autoPlayEnabled = enabled;
      _skipMode = mode;
      _next = result is NextEpisode ? result.episode : null;
      _preRollCancelled = false;
      _preRollShowing = false;
      _showSkipIntro = false;
      _showSkipOutro = false;
      _introSkipped = false;
      _outroSkipped = false;
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

    _applySkips(pos);

    // PRE-roll: surface the countdown during the final [_preRollLead] seconds,
    // counting down in step with playback. (Not a post-roll — it overlaps the
    // tail so the advance at end is instant.)
    if (_autoPlayEnabled && _next != null && !_preRollCancelled && total > 0) {
      final remaining = _duration - pos;
      if (remaining > Duration.zero && remaining <= _preRollLead) {
        // Countdown = min(5s, actual time remaining) — a seek to 3s-left starts
        // at 3, not a fixed 5. (ceil of the seconds left; remaining > 0 here.)
        final secs = math.min(
          _preRollLead.inSeconds,
          (remaining.inMilliseconds + 999) ~/ 1000,
        );
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

  /// Intro/outro handling per the current [_skipMode], driven by cached windows
  /// on [_shown] (offline — no network). Intro skip seeks to the window end;
  /// outro skip seeks past the credits WITHIN the episode (never advances).
  void _applySkips(Duration pos) {
    if (_skipMode == SkipMode.off) {
      if (_showSkipIntro || _showSkipOutro) {
        setState(() {
          _showSkipIntro = false;
          _showSkipOutro = false;
        });
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
        _seekPastOutro(outro); // skip credits WITHIN the episode (not advance)
      }
      return;
    }

    // Button mode: toggle the affordance. Hide the outro button while the
    // auto-play pre-roll card occupies the same corner.
    final showIntro = inIntro;
    final showOutro = inOutro && !_preRollShowing;
    if (showIntro != _showSkipIntro || showOutro != _showSkipOutro) {
      setState(() {
        _showSkipIntro = showIntro;
        _showSkipOutro = showOutro;
      });
    }
  }

  void _skipIntro() {
    final intro = _shown.introSkip;
    if (intro != null) _playback.seekTo(intro.end);
    setState(() => _showSkipIntro = false);
  }

  void _skipOutro() {
    final outro = _shown.outroSkip;
    if (outro != null) _seekPastOutro(outro);
    setState(() => _showSkipOutro = false);
  }

  /// Skip credits by seeking to the END of the outro window — staying in the
  /// episode so any post-credits scene plays. NOT advanceToNext (advancing is
  /// only the end-of-episode up-next countdown). If the AniSkip window overhangs
  /// the file, clamp to the end and the episode just completes naturally.
  void _seekPastOutro(SkipRange outro) {
    final target = (_duration > Duration.zero && outro.end > _duration)
        ? _duration
        : outro.end;
    _playback.seekTo(target);
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

  /// The one advance path. Both triggers — the pre-roll reaching the end and
  /// "Play now" — go through here. On success it updates the frame and tells
  /// the host (so the list follows); at a season boundary it stops cleanly.
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
    widget.onEpisodeChanged?.call(next);
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
    // A true-black "stage" so letterboxing reads as theater, not a gap.
    return ColoredBox(
      color: const Color(0xFF0A0A0B),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: Video(controller: _playback.controller)),
          // Skip-region timeline: shaded OP/ED spans over the episode duration.
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: _SkipMarkersBar(
              duration: _duration,
              intro: _shown.introSkip,
              outro: _shown.outroSkip,
            ),
          ),
          if (_showSkipIntro)
            Positioned(
              right: 16,
              bottom: 56,
              child: FilledButton.icon(
                onPressed: _skipIntro,
                icon: const Icon(Icons.fast_forward),
                label: const Text('Skip Intro'),
              ),
            ),
          if (_showSkipOutro)
            Positioned(
              right: 16,
              bottom: 56,
              child: FilledButton.icon(
                onPressed: _skipOutro,
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip Outro'),
              ),
            ),
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

/// Fractional `[start, end]` of a skip window across a [totalMs]-long episode,
/// CLAMPED to `[0, 1]` — so an outro window that overhangs the file end never
/// draws past the bar. Null when there's nothing to draw: no window, unknown
/// duration, or a degenerate span. Pure, so it's unit-testable.
@visibleForTesting
({double start, double end})? skipSpanFraction(SkipRange? r, int totalMs) {
  if (r == null || totalMs <= 0) return null;
  final start = (r.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
  final end = (r.end.inMilliseconds / totalMs).clamp(0.0, 1.0);
  if (end <= start) return null;
  return (start: start, end: end);
}

/// A thin timeline strip shading the cached intro (OP) and outro (ED) skip
/// windows over the episode's duration, so the user can see where they are.
/// Purely informational — reads the windows the player already holds, no fetch.
/// Each span is positioned by its fraction of the duration and CLAMPED to
/// [0, 1], so an outro window that overhangs the file end never draws past the
/// bar; a null window draws nothing (partial AniSkip coverage is normal).
class _SkipMarkersBar extends StatelessWidget {
  const _SkipMarkersBar({
    required this.duration,
    required this.intro,
    required this.outro,
  });

  final Duration duration;
  final SkipRange? intro;
  final SkipRange? outro;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    if (total <= 0) return const SizedBox.shrink(); // duration not known yet
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final children = <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ];
          void addRegion(SkipRange? r, Color color) {
            final span = skipSpanFraction(r, total);
            if (span == null) return;
            children.add(
              Positioned(
                top: 0,
                bottom: 0,
                left: w * span.start,
                width: w * (span.end - span.start),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }

          addRegion(intro, scheme.primary.withValues(alpha: 0.85));
          addRegion(outro, scheme.tertiary.withValues(alpha: 0.85));
          return Stack(children: children);
        },
      ),
    );
  }
}
