import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';

/// Thin wrapper around media_kit's [Player] + [VideoController] (libmpv).
///
/// The single place that owns playback engine objects. The UI hands it a domain
/// [Episode] — never a raw path or a data-layer type — and gets a
/// [VideoController] to render plus position/duration streams to report
/// progress (Stage 6 watch state).
class PlaybackController {
  PlaybackController() : player = Player() {
    controller = VideoController(player);
  }

  final Player player;
  late final VideoController controller;

  /// Play [episode], resuming at [startAt]. media_kit normalizes the plain path
  /// for libmpv — robust to spaces and `[brackets]` in release filenames.
  Future<void> open(Episode episode, {Duration startAt = Duration.zero}) {
    return player.open(
      Media(episode.fileRef, start: startAt > Duration.zero ? startAt : null),
    );
  }

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;

  Future<void> dispose() => player.dispose();
}
