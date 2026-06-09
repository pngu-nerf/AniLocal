import '../models/episode.dart';
import '../models/library_folder.dart';
import '../models/series.dart';

/// The UI's read path into the library. Backed by the local cache (seam #2);
/// the UI never waits on the network. Implementations live in the data layer —
/// this interface is all the UI is allowed to know about.
abstract interface class LibraryRepository {
  Future<List<LibraryFolder>> watchedFolders();
  Future<void> addFolder(String path);
  Future<void> removeFolder(LibraryFolder folder);

  Future<List<Series>> allSeries();
  Future<List<Episode>> episodesFor(int anilistId);
}
