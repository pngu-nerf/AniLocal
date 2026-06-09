import '../models/episode.dart';

/// Local-only watch state: watched flags and resume positions, keyed by an
/// episode's `fileRef`. No tracker, no sync, no outbox (roadmap Stage 6).
abstract interface class WatchStateRepository {
  Future<void> markWatched(String fileRef, {required bool watched});
  Future<void> saveResumePosition(String fileRef, Duration position);

  /// Episodes with progress but not finished — powers the "Continue watching" row.
  Future<List<Episode>> continueWatching();
}
