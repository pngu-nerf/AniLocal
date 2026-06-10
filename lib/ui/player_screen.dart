import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';
import '../domain/repositories/watch_state_repository.dart';
import '../playback/playback_controller.dart';

/// Plays one episode embedded with libmpv (media_kit) — styled ASS subtitles,
/// seeking, no external window. Resumes from the episode's saved position,
/// saves progress as it plays, and marks the episode watched past a threshold.
///
/// All watch-state writes go through the [WatchStateRepository] keyed by the
/// episode's identity (it reports position; what's stored is the episode).
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.episode,
    required this.watchState,
  });

  final Episode episode;
  final WatchStateRepository watchState;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Count an episode "watched" at 90%: enough to skip the ED/next-episode
  // preview (~1.5–2 min of a ~24 min episode) and still have it count.
  static const double _watchedThreshold = 0.90;

  final PlaybackController _playback = PlaybackController();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  Timer? _saveTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _markedWatched = false;

  @override
  void initState() {
    super.initState();
    _playback.open(widget.episode, startAt: widget.episode.resumePosition);
    _durSub = _playback.durationStream.listen((d) => _duration = d);
    _posSub = _playback.positionStream.listen(_onPosition);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
  }

  void _onPosition(Duration pos) {
    _position = pos;
    final total = _duration.inMilliseconds;
    if (!_markedWatched &&
        total > 0 &&
        pos.inMilliseconds >= total * _watchedThreshold) {
      _markedWatched = true;
      widget.watchState.setWatched(widget.episode, watched: true);
    }
  }

  void _persist() {
    if (_markedWatched) return; // already finished; resume was cleared
    if (_duration.inMilliseconds <= 0 || _position.inMilliseconds <= 0) return;
    widget.watchState.saveProgress(
      widget.episode,
      position: _position,
      duration: _duration,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _persist(); // best-effort final save (fire-and-forget)
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.episode.title ?? 'Episode ${widget.episode.number}'),
      ),
      // Video brings the media_kit controls overlay (seek bar included).
      body: Video(controller: _playback.controller),
    );
  }
}
