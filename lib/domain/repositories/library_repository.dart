import '../models/episode.dart';
import '../models/identified_episode.dart';
import '../models/library_folder.dart';
import '../models/series.dart';

/// The UI's read path into the library. Backed by the local cache (seam #2);
/// the UI never waits on the network. Implementations live in the data layer —
/// this interface is all the UI is allowed to know about.
abstract interface class LibraryRepository {
  Future<List<LibraryFolder>> watchedFolders();
  Future<void> addFolder(String path);
  Future<void> removeFolder(LibraryFolder folder);

  /// Persist a new priority order for the watched folders (index 0 = highest
  /// priority / preferred default source). Multi-source episodes on Automatic
  /// re-resolve their default to this order on the next read — no rescan, no
  /// network. Per-episode source pins are untouched (seam #5).
  Future<void> reorderFolders(List<LibraryFolder> orderedFolders);

  /// All matched series in the library (for the grid).
  Future<List<Series>> allSeries();

  /// Episodes (matched files) for a series, ordered by episode number.
  Future<List<Episode>> episodesFor(int anilistId);

  /// Files that scanned but matched no AniList entry — kept on record so they
  /// don't vanish on rescan (Stage 5 fix-match will resolve them).
  Future<List<IdentifiedEpisode>> unmatchedFiles();
}
