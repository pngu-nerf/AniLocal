import '../../domain/models/continue_watching.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/library_folder.dart';
import '../../domain/models/series.dart';
import '../../domain/models/titles.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/watch_state_repository.dart';
import 'cache_database.dart';

/// The effective match for a file after applying any override.
class _Effective {
  _Effective({
    required this.file,
    required this.anilistId,
    required this.displayNumber,
    required this.anchoredNumber,
  });

  final CachedFileRow file;
  final int? anilistId; // null = unmatched
  final int? displayNumber; // presentation number (continuous or faithful)
  final int anchoredNumber; // AniList-faithful position = watch-state identity
}

/// Cache-backed read path (seam #2). Maps Drift rows to domain models — no Drift
/// type leaks out. Reads never touch the network.
///
/// Merges three stores: the auto-match (`file_cache`), user overrides
/// (`match_overrides`, which win), and watch state (`watch_state`, keyed by
/// episode identity = AniList entry + anchored position). Also implements the
/// watch-state writes, all keyed by that same identity (never by file path).
class DriftLibraryRepository
    implements LibraryRepository, WatchStateRepository {
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
            final anchored = o.anchoredEpisode ?? 0;
            final display = o.displayContinuous
                ? anchored + o.continuousOffset
                : o.anchoredEpisode;
            return _Effective(
              file: f,
              anilistId: o.anilistId,
              displayNumber: display,
              anchoredNumber: anchored,
            );
          }
          return _Effective(
            file: f,
            anilistId: f.anilistId,
            displayNumber: f.episodeNumber,
            anchoredNumber: f.episodeNumber ?? 0,
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
    final watch = {
      for (final w in await _db.allWatchStateRows())
        (w.anilistId, w.episode): w,
    };
    final mine = effective.where((e) => e.anilistId == anilistId).toList()
      ..sort((a, b) => (a.displayNumber ?? 0).compareTo(b.displayNumber ?? 0));
    return [
      for (final e in mine) _toEpisode(e, watch[(anilistId, e.anchoredNumber)]),
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

  // --- Watch state (keyed by episode identity, never file path) ---

  @override
  Future<void> saveProgress(
    Episode episode, {
    required Duration position,
    required Duration duration,
  }) {
    return _db.upsertWatchState(
      WatchStateRow(
        anilistId: episode.seriesAnilistId,
        episode: episode.anchoredNumber,
        resumePositionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        watched: false,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> setWatched(Episode episode, {required bool watched}) async {
    final existing = await _db.watchStateFor(
      episode.seriesAnilistId,
      episode.anchoredNumber,
    );
    await _db.upsertWatchState(
      WatchStateRow(
        anilistId: episode.seriesAnilistId,
        episode: episode.anchoredNumber,
        // Marking watched clears resume so it leaves "Continue watching".
        resumePositionMs: watched ? 0 : (existing?.resumePositionMs ?? 0),
        durationMs: existing?.durationMs ?? episode.duration.inMilliseconds,
        watched: watched,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> clearProgress(Episode episode) =>
      _db.deleteWatchState(episode.seriesAnilistId, episode.anchoredNumber);

  @override
  Future<List<ContinueWatching>> continueWatching() async {
    final inProgress = await _db
        .inProgressWatchStates(); // ordered, recent first
    final effective = await _effectiveMatches();
    final fileByIdentity = <(int, int), _Effective>{};
    for (final e in effective) {
      if (e.anilistId != null) {
        fileByIdentity.putIfAbsent((e.anilistId!, e.anchoredNumber), () => e);
      }
    }
    final seriesById = {
      for (final r in await _db.allSeriesRows()) r.anilistId: r,
    };

    final result = <ContinueWatching>[];
    for (final w in inProgress) {
      final match = fileByIdentity[(w.anilistId, w.episode)];
      final series = seriesById[w.anilistId];
      if (match == null || series == null) continue; // file/series gone
      result.add(
        ContinueWatching(
          series: _toSeries(series),
          episode: _toEpisode(match, w),
        ),
      );
    }
    return result;
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

  Episode _toEpisode(_Effective e, WatchStateRow? w) => Episode(
    number: e.displayNumber ?? 0,
    fileRef: e.file.path,
    title: e.displayNumber != null ? 'Episode ${e.displayNumber}' : null,
    seriesAnilistId: e.anilistId ?? 0,
    anchoredNumber: e.anchoredNumber,
    watched: w?.watched ?? false,
    resumePosition: Duration(milliseconds: w?.resumePositionMs ?? 0),
    duration: Duration(milliseconds: w?.durationMs ?? 0),
  );

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
