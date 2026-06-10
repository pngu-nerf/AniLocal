import '../../domain/models/episode.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/library_folder.dart';
import '../../domain/models/series.dart';
import '../../domain/models/titles.dart';
import '../../domain/repositories/library_repository.dart';
import 'cache_database.dart';

/// Cache-backed read path (seam #2). Maps Drift rows to domain models — no
/// Drift type leaks out. Reads never touch the network; the pipeline fills the
/// cache separately (LibrarySync).
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);

  final CacheDatabase _db;

  @override
  Future<List<Series>> allSeries() async {
    final rows = await _db.allSeriesRows();
    final list = rows.map(_toSeries).toList()
      ..sort((a, b) => _sortTitle(a).compareTo(_sortTitle(b)));
    return list;
  }

  @override
  Future<List<Episode>> episodesFor(int anilistId) async {
    final rows = await _db.filesForSeries(anilistId);
    rows.sort((a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
    return [
      for (final f in rows)
        Episode(
          number: f.episodeNumber ?? 0,
          fileRef: f.path,
          title: f.episodeNumber != null ? 'Episode ${f.episodeNumber}' : null,
        ),
    ];
  }

  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async {
    final rows = await _db.unmatchedFileRows();
    return [
      for (final f in rows)
        IdentifiedEpisode(
          filePath: f.path,
          parsedTitle: f.parsedTitle,
          parsedEpisodeNumber: f.episodeNumber,
          releaseGroup: f.releaseGroup,
          matchScore: f.matchScore,
        ),
    ];
  }

  // Multi-folder management arrives in Stage 5; the folder is a hardcoded spike
  // constant for now.
  @override
  Future<List<LibraryFolder>> watchedFolders() async => const [];

  @override
  Future<void> addFolder(String path) async =>
      throw UnsupportedError('Multi-folder management arrives in Stage 5');

  @override
  Future<void> removeFolder(LibraryFolder folder) async =>
      throw UnsupportedError('Multi-folder management arrives in Stage 5');

  Series _toSeries(CachedSeriesRow r) => Series(
    anilistId: r.anilistId,
    titles: Titles(romaji: r.romaji, english: r.english, native: r.nativeTitle),
    format: r.format,
    episodeCount: r.episodeCount,
    // The LOCAL art path, so offline browse shows art (not the remote URL).
    coverImageRef: r.coverImagePath,
  );

  String _sortTitle(Series s) =>
      (s.titles.english ?? s.titles.romaji ?? s.titles.native ?? '')
          .toLowerCase();
}
