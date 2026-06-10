import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';
import '../playback/playback_controller.dart';

/// Plays one episode embedded with libmpv (media_kit) — styled ASS subtitles,
/// seeking, no external window. Receives a domain [Episode]; the path is
/// resolved by the repository upstream and the playback seam owns the engine.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.episode});

  final Episode episode;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlaybackController _playback = PlaybackController();

  @override
  void initState() {
    super.initState();
    _playback.open(widget.episode);
  }

  @override
  void dispose() {
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
