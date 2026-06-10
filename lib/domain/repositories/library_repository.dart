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

  /// All matched series in the library (for the grid).
  Future<List<Series>> allSeries();

  /// Episodes (matched files) for a series, ordered by episode number.
  Future<List<Episode>> episodesFor(int anilistId);

  /// Files that scanned but matched no AniList entry — kept on record so they
  /// don't vanish on rescan (Stage 5 fix-match will resolve them).
  Future<List<IdentifiedEpisode>> unmatchedFiles();
}
