import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/models/episode.dart';
import '../domain/models/next_result.dart';
import '../domain/repositories/watch_order_repository.dart';

/// Thin wrapper around media_kit's [Player] + [VideoController] (libmpv).
///
/// The single place that owns playback engine objects. The UI hands it a domain
/// [Episode] — never a raw path or a data-layer type — and gets a
/// [VideoController] to render plus position/duration/completed streams. It also
/// owns the one advance-to-next action ([advanceToNext]).
class PlaybackController {
  PlaybackController({required this.resolver}) : player = Player() {
    controller = VideoController(player);
  }

  final Player player;
  late final VideoController controller;

  /// Single source of "what's next" — consulted by [advanceToNext].
  final WatchOrderRepository resolver;

  Episode? _current;

  /// The episode currently loaded (null before the first [open]).
  Episode? get current => _current;

  /// Play [episode], resuming at [startAt]. media_kit normalizes the plain path
  /// for libmpv — robust to spaces and `[brackets]` in release filenames.
  Future<void> open(Episode episode, {Duration startAt = Duration.zero}) {
    _current = episode;
    return player.open(
      Media(episode.fileRef, start: startAt > Duration.zero ? startAt : null),
    );
  }

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;

  /// Emits `true` when the current media finishes.
  Stream<bool> get completedStream => player.stream.completed;

  /// THE advance-to-next action — one entry point, callable by any trigger
  /// (the auto-play countdown today; a future "seek past the end" handler).
  /// Asks the resolver what follows [current]: if there's a next episode it
  /// plays it and returns it; at a season boundary ([NoNextEpisode]) it stops
  /// and returns null. Advancing never computes "next" itself — it routes
  /// through the resolver like every other caller.
  Future<Episode?> advanceToNext() async {
    final cur = _current;
    if (cur == null) return null;
    final result = await resolver.nextEpisode(cur);
    if (result is NextEpisode) {
      await open(result.episode, startAt: result.episode.resumePosition);
      return result.episode;
    }
    return null; // NoNextEpisode -> stop
  }

  Future<void> dispose() => player.dispose();
}
