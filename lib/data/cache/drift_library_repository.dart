import '../../domain/models/episode.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/library_folder.dart';
import '../../domain/models/series.dart';
import '../../domain/models/titles.dart';
import '../../domain/repositories/library_repository.dart';
import 'cache_database.dart';

/// The effective match for a file after applying any override.
class _Effective {
  _Effective({
    required this.file,
    required this.anilistId,
    required this.displayNumber,
  });

  final CachedFileRow file;
  final int? anilistId; // null = unmatched
  final int? displayNumber;
}

/// Cache-backed read path (seam #2). Maps Drift rows to domain models — no
/// Drift type leaks out. Reads never touch the network.
///
/// The read MERGES the auto-match (`file_cache`, recomputed each scan) with the
/// user override store (`match_overrides`): if an override exists for a file's
/// content fingerprint, the override IS the match and the auto-guess is ignored.
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);

  final CacheDatabase _db;

  /// Build the effective (override-or-auto) match for every cached file.
  Future<List<_Effective>> _effectiveMatches() async {
    final files = await _db.allFileRows();
    final overrides = {
      for (final o in await _db.allOverrideRows())
        (o.fileSize, o.modifiedAtMs): o,
    };
    return [
      for (final f in files)
        () {
          final o = overrides[(f.fileSize, f.modifiedAtMs)];
          if (o != null) {
            final display = o.displayContinuous
                ? (o.anchoredEpisode ?? 0) + o.continuousOffset
                : o.anchoredEpisode;
            return _Effective(
              file: f,
              anilistId: o.anilistId,
              displayNumber: display,
            );
          }
          return _Effective(
            file: f,
            anilistId: f.anilistId,
            displayNumber: f.episodeNumber,
          );
        }(),
    ];
  }

  @override
  Future<List<Series>> allSeries() async {
    final effective = await _effectiveMatches();
    final wanted = {
      for (final e in effective)
        if (e.anilistId != null) e.anilistId!,
    };
    final byId = {for (final r in await _db.allSeriesRows()) r.anilistId: r};
    final list = [
      for (final id in wanted)
        if (byId[id] != null) _toSeries(byId[id]!),
    ]..sort((a, b) => _sortTitle(a).compareTo(_sortTitle(b)));
    return list;
  }

  @override
  Future<List<Episode>> episodesFor(int anilistId) async {
    final effective = await _effectiveMatches();
    final mine = effective.where((e) => e.anilistId == anilistId).toList()
      ..sort((a, b) => (a.displayNumber ?? 0).compareTo(b.displayNumber ?? 0));
    return [
      for (final e in mine)
        Episode(
          number: e.displayNumber ?? 0,
          fileRef: e.file.path,
          title: e.displayNumber != null ? 'Episode ${e.displayNumber}' : null,
        ),
    ];
  }

  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async {
    final effective = await _effectiveMatches();
    return [
      for (final e in effective)
        if (e.anilistId == null)
          IdentifiedEpisode(
            filePath: e.file.path,
            parsedTitle: e.file.parsedTitle,
            parsedEpisodeNumber: e.file.episodeNumber,
            releaseGroup: e.file.releaseGroup,
            matchScore: e.file.matchScore,
          ),
    ];
  }

  @override
  Future<List<LibraryFolder>> watchedFolders() async {
    final rows = await _db.allFolderRows();
    return [for (final r in rows) LibraryFolder(path: r.path)];
  }

  @override
  Future<void> addFolder(String path) => _db.insertFolder(path);

  @override
  Future<void> removeFolder(LibraryFolder folder) =>
      _db.removeFolderAndFiles(folder.path);

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
