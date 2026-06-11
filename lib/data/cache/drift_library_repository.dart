import '../../domain/models/continue_watching.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/episode_source.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/next_result.dart';
import '../../domain/models/library_folder.dart';
import '../../domain/models/series.dart';
import '../../domain/models/skip_range.dart';
import '../../domain/models/titles.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/source_selection_repository.dart';
import '../../domain/repositories/watch_order_repository.dart';
import '../../domain/repositories/watch_state_repository.dart';
import 'cache_database.dart';

/// Sort rank for a file not under any known library folder (orphan from a
/// removed folder) — below every real folder, so it's the last-resort source.
const int _unfiledSortOrder = 1 << 30;

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

/// One LOGICAL episode = the files sharing an identity (anilistId, anchored),
/// collapsed to a single playable unit with its priority-ordered [sources] and
/// the resolved [activeFileRef] (manual source override if set, else priority).
class _Logical {
  _Logical({
    required this.anilistId,
    required this.anchored,
    required this.displayNumber,
    required this.sources,
    required this.activeFileRef,
    required this.pinnedFolder,
  });

  final int anilistId;
  final int anchored;
  final int? displayNumber;
  final List<EpisodeSource> sources; // priority-ordered (default = first)
  final String activeFileRef;
  final String? pinnedFolder; // in-effect manual pin, else null (automatic)
}

/// Cache-backed read path (seam #2). Maps Drift rows to domain models — no Drift
/// type leaks out. Reads never touch the network.
///
/// Merges three stores: the auto-match (`file_cache`), user overrides
/// (`match_overrides`, which win), and watch state (`watch_state`, keyed by
/// episode identity = AniList entry + anchored position). Also implements the
/// watch-state writes, all keyed by that same identity (never by file path).
class DriftLibraryRepository
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository {
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

  /// Collapse matched files into logical episodes keyed by identity
  /// (anilistId, anchored). Each gets its sources priority-ordered by the
  /// containing folder's sortOrder, and an active source resolved as:
  /// manual override (if its folder still holds the episode) else the
  /// highest-priority source. This is where multi-source de-duplication and
  /// source resolution live — entirely in the data layer (the UI sees one
  /// Episode per identity).
  Future<Map<(int, int), _Logical>> _logicalEpisodes() async {
    final effective = await _effectiveMatches();
    final folders = await _db.allFolderRows(); // sorted by sortOrder asc
    final overrides = {
      for (final o in await _db.allSourceOverrideRows())
        (o.anilistId, o.episode): o,
    };

    final groups = <(int, int), List<_Effective>>{};
    for (final e in effective) {
      if (e.anilistId == null) continue;
      groups.putIfAbsent((e.anilistId!, e.anchoredNumber), () => []).add(e);
    }

    final result = <(int, int), _Logical>{};
    groups.forEach((key, files) {
      final sources =
          [
            for (final e in files)
              () {
                final owner = _owningFolder(e.file.path, folders);
                return EpisodeSource(
                  fileRef: e.file.path,
                  folderPath: owner?.path ?? _parentDir(e.file.path),
                  folderSortOrder: owner?.sortOrder ?? _unfiledSortOrder,
                );
              }(),
          ]..sort((a, b) {
            final c = a.folderSortOrder.compareTo(b.folderSortOrder);
            return c != 0 ? c : a.fileRef.compareTo(b.fileRef);
          });

      // Resolve the active source: a manual override wins, but only while its
      // folder still holds the episode; otherwise fall back to priority. The
      // pin is "in effect" only when it actually selects a present source.
      var active = sources.first;
      String? pinnedFolder;
      final ov = overrides[key];
      if (ov != null) {
        final pinned = sources.where((s) => s.folderPath == ov.folderPath);
        if (pinned.isNotEmpty) {
          active = pinned.first;
          pinnedFolder = ov.folderPath;
        }
      }

      // Display number comes from the active source's effective match (all
      // sources are the same episode; normally identical).
      final activeEff = files.firstWhere((e) => e.file.path == active.fileRef);
      result[key] = _Logical(
        anilistId: key.$1,
        anchored: key.$2,
        displayNumber: activeEff.displayNumber,
        sources: sources,
        activeFileRef: active.fileRef,
        pinnedFolder: pinnedFolder,
      );
    });
    return result;
  }

  /// The library folder that owns [path] — the longest matching path prefix
  /// (most specific folder when folders nest). Null if none (orphan file).
  LibraryFolderRow? _owningFolder(String path, List<LibraryFolderRow> folders) {
    LibraryFolderRow? best;
    for (final f in folders) {
      if (path == f.path || path.startsWith('${f.path}/')) {
        if (best == null || f.path.length > best.path.length) best = f;
      }
    }
    return best;
  }

  String _parentDir(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? path : path.substring(0, i);
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
    final logical = await _logicalEpisodes();
    final watch = {
      for (final w in await _db.allWatchStateRows())
        (w.anilistId, w.episode): w,
    };
    final skips = {
      for (final s in await _db.allSkipRows()) (s.anilistId, s.episode): s,
    };
    final mine = [
      for (final l in logical.values)
        if (l.anilistId == anilistId) l,
    ]..sort((a, b) => (a.displayNumber ?? 0).compareTo(b.displayNumber ?? 0));
    return [
      for (final l in mine)
        _toEpisode(
          l,
          watch[(anilistId, l.anchored)],
          skips[(anilistId, l.anchored)],
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
    final logical = await _logicalEpisodes(); // one per episode identity
    final seriesById = {
      for (final r in await _db.allSeriesRows()) r.anilistId: r,
    };
    final skips = {
      for (final s in await _db.allSkipRows()) (s.anilistId, s.episode): s,
    };

    final result = <ContinueWatching>[];
    for (final w in inProgress) {
      final match = logical[(w.anilistId, w.episode)];
      final series = seriesById[w.anilistId];
      if (match == null || series == null) continue; // file/series gone
      result.add(
        ContinueWatching(
          series: _toSeries(series),
          episode: _toEpisode(match, w, skips[(w.anilistId, w.episode)]),
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

  @override
  Future<void> reorderFolders(List<LibraryFolder> orderedFolders) =>
      _db.reorderFolders([for (final f in orderedFolders) f.path]);

  // --- Source selection (multi-source). Sole writer of source_overrides;
  //     keyed by episode identity, never clobbered by a rescan (seam #5). ---

  @override
  Future<void> selectSource(Episode episode, {required String folderPath}) =>
      _db.upsertSourceOverride(
        SourceOverrideRow(
          anilistId: episode.seriesAnilistId,
          episode: episode.anchoredNumber,
          folderPath: folderPath,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> clearSource(Episode episode) =>
      _db.deleteSourceOverride(episode.seriesAnilistId, episode.anchoredNumber);

  // --- Watch order ("Up Next"). The SINGLE source of "what's next" — every
  //     caller (player auto-advance, library "Next: Ep N") routes through here.
  //
  //     WITHIN-SEASON only today: the next anchored episode in the same series,
  //     else [NoNextEpisode]. That NoNextEpisode at a season boundary is the
  //     correct end-of-season answer now AND the deliberate seam where
  //     cross-season slots in later (follow the AniList SEQUEL relation at
  //     exactly this point) — one function changes, no caller does. ---

  @override
  Future<NextResult> nextEpisode(Episode current) async {
    final logical = await _logicalEpisodes();
    final next = _resolveNext(
      current.seriesAnilistId,
      current.anchoredNumber,
      logical,
    );
    if (next == null) return const NoNextEpisode();
    final w = await _db.watchStateFor(next.anilistId, next.anchored);
    final skip = await _db.skipSegmentFor(next.anilistId, next.anchored);
    return NextEpisode(_toEpisode(next, w, skip));
  }

  @override
  Future<Map<int, Episode>> upNextBySeries() async {
    final logical = await _logicalEpisodes();
    final watch = {
      for (final w in await _db.allWatchStateRows())
        (w.anilistId, w.episode): w,
    };
    final skips = {
      for (final s in await _db.allSkipRows()) (s.anilistId, s.episode): s,
    };

    // Furthest WATCHED anchored position per series the user has started.
    final latestWatched = <int, int>{};
    for (final w in watch.values) {
      if (!w.watched) continue;
      final cur = latestWatched[w.anilistId];
      if (cur == null || w.episode > cur) {
        latestWatched[w.anilistId] = w.episode;
      }
    }

    final result = <int, Episode>{};
    latestWatched.forEach((anilistId, anchored) {
      // Same resolver as nextEpisode — within-season next.
      final next = _resolveNext(anilistId, anchored, logical);
      if (next == null) return; // NoNextEpisode -> caught up, show nothing
      final w = watch[(next.anilistId, next.anchored)];
      if (w?.watched ?? false) return; // already watched -> nothing "next"
      result[anilistId] = _toEpisode(
        next,
        w,
        skips[(next.anilistId, next.anchored)],
      );
    });
    return result;
  }

  /// The logical episode after (anilistId, anchored) WITHIN the same series, or
  /// null at the season boundary (the series' last in-library episode). The
  /// null is the seam where cross-season will later follow the SEQUEL relation.
  _Logical? _resolveNext(
    int anilistId,
    int anchored,
    Map<(int, int), _Logical> logical,
  ) => logical[(anilistId, anchored + 1)];

  Episode _toEpisode(_Logical l, WatchStateRow? w, SkipSegmentRow? skip) =>
      Episode(
        number: l.displayNumber ?? 0,
        fileRef: l.activeFileRef,
        title: l.displayNumber != null ? 'Episode ${l.displayNumber}' : null,
        seriesAnilistId: l.anilistId,
        anchoredNumber: l.anchored,
        watched: w?.watched ?? false,
        resumePosition: Duration(milliseconds: w?.resumePositionMs ?? 0),
        duration: Duration(milliseconds: w?.durationMs ?? 0),
        sources: l.sources,
        pinnedSourceFolder: l.pinnedFolder,
        introSkip: _range(skip?.introStartMs, skip?.introEndMs),
        outroSkip: _range(skip?.outroStartMs, skip?.outroEndMs),
      );

  /// Build a [SkipRange] when both bounds are present, else null.
  SkipRange? _range(int? startMs, int? endMs) =>
      (startMs != null && endMs != null)
      ? SkipRange(
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: endMs),
        )
      : null;

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
