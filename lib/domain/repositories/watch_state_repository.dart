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

  /// AUTO (threshold-derived) watched mark. Marking watched clears the resume
  /// position (a finished episode leaves "Continue watching"). RESPECTS a manual
  /// override: if the episode was set by [setWatchedManual], this is a no-op —
  /// the manual value wins over the threshold.
  Future<void> setWatched(Episode episode, {required bool watched});

  /// MANUAL, sticky watched-override (the per-episode toggle). Wins over the
  /// auto/threshold path and survives re-entry AND metadata refresh/rescan.
  /// Does NOT change the saved resume position (progress is untouched).
  Future<void> setWatchedManual(Episode episode, {required bool watched});

  /// Dismiss [episode] from "Continue watching" — removes its in-progress
  /// state without marking it watched.
  Future<void> clearProgress(Episode episode);

  /// In-progress episodes (resume > 0, not yet watched), most-recent first.
  Future<List<ContinueWatching>> continueWatching();
}
