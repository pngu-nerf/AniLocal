import '../models/continue_watching.dart';
import '../models/episode.dart';

/// Local-only watch state — watched flags + resume positions, keyed by EPISODE
/// IDENTITY (AniList entry + anchored position), never by file path or player
/// session. No tracker, no sync, no network, no outbox (roadmap Stage 6).
abstract interface class WatchStateRepository {
  /// Persist an in-progress resume position for [episode].
  Future<void> saveProgress(
    Episode episode, {
    required Duration position,
    required Duration duration,
  });

  /// Mark [episode] watched/unwatched. Marking watched clears the resume
  /// position (a finished episode leaves "Continue watching").
  Future<void> setWatched(Episode episode, {required bool watched});

  /// Dismiss [episode] from "Continue watching" — removes its in-progress
  /// state without marking it watched.
  Future<void> clearProgress(Episode episode);

  /// In-progress episodes (resume > 0, not yet watched), most-recent first.
  Future<List<ContinueWatching>> continueWatching();
}
