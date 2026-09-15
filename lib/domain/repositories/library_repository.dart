import '../models/episode.dart';
import '../models/identified_episode.dart';
import '../models/library_folder.dart';
import '../models/library_snapshot.dart';
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

  /// One show by id, or null when it is no longer in the library (pruned by a
  /// rescan, or re-identified under another id). The live re-read for a screen
  /// that was pushed with a `Series` and must not keep showing a stale one.
  Future<Series?> seriesById(int seriesId);

  /// Everything the library screen renders, in ONE pass — see
  /// [LibrarySnapshot] for why the five reads it replaces are not issued
  /// separately.
  Future<LibrarySnapshot> snapshot();

  /// How many files a source confirmed it could not identify. A COUNT, not
  /// the rows: the two callers show a number.
  Future<int> unmatchedCount();

  /// Episodes (matched files) for a series, ordered by episode number.
  Future<List<Episode>> episodesFor(int seriesId);

  /// Every series' episodes in ONE read, keyed by series id (placeholders
  /// included, under their synthetic ids). The library grid needs a stat per
  /// card; calling [episodesFor] once per card rebuilt the whole library N
  /// times over.
  Future<Map<int, List<Episode>>> episodesBySeries();

  /// Files that scanned but matched no entry in any source — kept on record so they
  /// don't vanish on rescan (Stage 5 fix-match will resolve them).
  Future<List<IdentifiedEpisode>> unmatchedFiles();
}
