import '../models/series.dart';

/// The UI's entry point for manual match correction. Implemented in the data
/// layer by the service that exclusively owns the override store — the UI never
/// imports that service, and the auto-matcher never imports this (seam #5).
abstract interface class FixMatchRepository {
  /// Ranked AniList candidates for a query (top result is unreliable; the user
  /// picks).
  Future<List<Series>> searchCandidates(String query);

  /// Assign or reassign a single file to [chosen].
  Future<void> assignFile({
    required String filePath,
    required Series chosen,
    int? anchoredEpisode,
    int continuousOffset,
    bool displayContinuous,
  });

  /// Split: assign an ordered run of files to [chosen], anchoring the first at
  /// [anchorStart] within that entry. Files do not move on disk.
  Future<void> assignRange({
    required List<String> filePaths,
    required Series chosen,
    int anchorStart,
    int continuousOffset,
    bool displayContinuous,
  });

  /// Revert a file to its auto-match.
  Future<void> clearOverride(String filePath);
}
