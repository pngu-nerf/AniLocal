import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';

/// Thin wrapper around media_kit's [Player] + [VideoController] (libmpv).
///
/// The single place that owns playback engine objects. The UI hands it a domain
/// [Episode] — never a raw path or a data-layer type — and gets a
/// [VideoController] to render. Online vs offline / where the file came from is
/// invisible here.
class PlaybackController {
  PlaybackController() : player = Player() {
    controller = VideoController(player);
  }

  final Player player;
  late final VideoController controller;

  /// Play [episode]'s file. The plain absolute path is passed to media_kit,
  /// which normalizes it for libmpv — robust to spaces and `[brackets]` in real
  /// release filenames (a `file://` string would mis-parse those).
  Future<void> open(Episode episode) => player.open(Media(episode.fileRef));

  Future<void> dispose() => player.dispose();
}
