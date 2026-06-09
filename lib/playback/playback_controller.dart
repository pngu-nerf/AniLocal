import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Thin wrapper around media_kit's [Player] + [VideoController] (libmpv).
///
/// This is the single place that owns playback engine objects. The UI gets a
/// [VideoController] to render and a [Player] to drive transport; it never
/// constructs media_kit objects itself. Stage 1 just opens one local file.
class PlaybackController {
  PlaybackController() : player = Player() {
    controller = VideoController(player);
  }

  final Player player;
  late final VideoController controller;

  /// Open a local file by absolute path and start playing.
  Future<void> openFile(String absolutePath) {
    return player.open(Media('file://$absolutePath'));
  }

  Future<void> dispose() => player.dispose();
}
