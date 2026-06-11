import '../models/episode.dart';

/// The UI's entry point for choosing which source a multi-source episode plays
/// from. Writes a manual override keyed by the episode's identity
/// (`seriesAnilistId` + `anchoredNumber`) — the same identity watch state uses,
/// so the choice is per logical episode, not per file.
///
/// The override is sacred across rescans (seam #5, source dimension): the
/// auto-matcher's fill path never writes it, so a manual choice survives — even
/// if a higher-priority folder later gains the episode.
abstract interface class SourceSelectionRepository {
  /// Pin [episode] to play from the copy in [folderPath]. Beats the
  /// folder-priority default until cleared.
  Future<void> selectSource(Episode episode, {required String folderPath});

  /// Drop the manual choice — revert to the folder-priority default.
  Future<void> clearSource(Episode episode);
}
