import '../../domain/models/continue_watching.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/external_ids.dart';
import '../../domain/models/episode_source.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/next_result.dart';
import '../../domain/models/library_folder.dart';
import '../../domain/models/picture_mode.dart';
import '../../domain/models/series.dart';
import '../../domain/models/show_preferences.dart';
import '../../domain/models/skip_range.dart';
import '../../domain/skip_corroboration.dart';
import '../../domain/models/titles.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/missing_episodes_repository.dart';
import '../../domain/repositories/show_preferences_repository.dart';
import '../../domain/repositories/source_selection_repository.dart';
import '../../domain/repositories/watch_order_repository.dart';
import '../../domain/repositories/watch_state_repository.dart';
import '../folders/volume_resolver.dart';
import '../scanner/title_matching.dart' show normalizeTitle;
import 'cache_database.dart';
import 'series_identity.dart';

/// Sort rank for a file not under any known library folder (orphan from a
/// removed folder) — below every real folder, so it's the last-resort source.
const int _unfiledSortOrder = 1 << 30;

/// The effective match for a file after applying any override.
class _Effective {
  _Effective({
    required this.file,
    required this.seriesId,
    required this.displayNumber,
    required this.anchoredNumber,
    required this.pending,
  });

  final CachedFileRow file;
  final int? seriesId; // null = unmatched (pending or confirmed)
  final int? displayNumber; // presentation number (continuous or faithful)
  final int anchoredNumber; // AniList-faithful position = watch-state identity

  /// Meaningful only when [seriesId] is null: true = pending (not yet
  /// identified → shown as a placeholder), false = confirmed-unmatched (→
  /// fix-match screen). A file resolved via an override is never pending.
  final bool pending;
}

/// One LOGICAL episode = the files sharing an identity (seriesId, anchored),
/// collapsed to a single playable unit with its priority-ordered [sources] and
/// the resolved [activeFileRef] (manual source override if set, else priority).
class _Logical {
  _Logical({
    required this.seriesId,
    required this.anchored,
    required this.displayNumber,
    required this.sources,
    required this.activeFileRef,
    required this.pinnedFolder,
  });

  final int seriesId;
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
        WatchOrderRepository,
        MissingEpisodesRepository,
        ShowPreferencesRepository {
  DriftLibraryRepository(this._db, {VolumeResolver? resolver})
    : _resolver = resolver ?? DiskutilVolumeResolver();

  final CacheDatabase _db;

  /// Resolves a file's CURRENT absolute path by following its owning folder's
  /// volume across remounts (defaults to the macOS diskutil resolver; injectable
  /// for tests). The fast path (stored folder path still exists) calls nothing.
  final VolumeResolver _resolver;

  /// Map each library folder's stable identity to its CURRENT absolute path
  /// (null when its volume isn't mounted). Resolved once per read.
  Future<Map<String, String?>> _currentFolderPaths(
    List<LibraryFolderRow> folders,
  ) async {
    final result = <String, String?>{};
    for (final f in folders) {
      result[f.path] = await resolveFolderPath(
        storedPath: f.path,
        volumeId: f.volumeId,
        volumeSubpath: f.volumeSubpath,
        resolver: _resolver,
      );
    }
    return result;
  }

  /// The current absolute path the player should open for [f]: its owning
  /// folder's current mount joined with the file's relative path. Falls back to
  /// the stable folder path when the volume is missing (the show is greyed
  /// offline anyway), so a fileRef is always a non-empty string.
  String _fileRef(CachedFileRow f, Map<String, String?> currentByFolder) {
    final current = currentByFolder[f.folderPath] ?? f.folderPath;
    return f.relativePath.isEmpty ? current : '$current/${f.relativePath}';
  }

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
            // An override (user fix-match) makes the file matched — never
            // pending — even if its auto row was still a pending placeholder.
            return _Effective(
              file: f,
              seriesId: o.seriesId,
              displayNumber: display,
              anchoredNumber: anchored,
              pending: false,
            );
          }
          return _Effective(
            file: f,
            seriesId: f.seriesId,
            displayNumber: f.episodeNumber,
            anchoredNumber: f.episodeNumber ?? 0,
            pending: f.seriesId == null && f.pendingIdentification,
          );
        }(),
    ];
  }

  /// Collapse matched files into logical episodes keyed by identity
  /// (seriesId, anchored). Each gets its sources priority-ordered by the
  /// containing folder's sortOrder, and an active source resolved as:
  /// manual override (if its folder still holds the episode) else the
  /// highest-priority source. This is where multi-source de-duplication and
  /// source resolution live — entirely in the data layer (the UI sees one
  /// Episode per identity).
  Future<Map<(int, int), _Logical>> _logicalEpisodes() async {
    final effective = await _effectiveMatches();
    final folders = await _db.allFolderRows(); // sorted by sortOrder asc
    final folderByPath = {for (final f in folders) f.path: f};
    final currentByFolder = await _currentFolderPaths(folders);
    final overrides = {
      for (final o in await _db.allSourceOverrideRows())
        (o.seriesId, o.episode): o,
    };

    final groups = <(int, int), List<_Effective>>{};
    for (final e in effective) {
      if (e.seriesId == null) continue;
      groups.putIfAbsent((e.seriesId!, e.anchoredNumber), () => []).add(e);
    }

    final result = <(int, int), _Logical>{};
    groups.forEach((key, files) {
      // Build (source, effective) per file. The owning folder is STORED on the
      // row (file.folderPath, the folder's stable identity), so there's no
      // path-prefix matching; fileRef is resolved to the volume's current mount.
      final entries =
          [
            for (final e in files)
              (
                source: EpisodeSource(
                  fileRef: _fileRef(e.file, currentByFolder),
                  folderPath: e.file.folderPath,
                  folderSortOrder:
                      folderByPath[e.file.folderPath]?.sortOrder ??
                      _unfiledSortOrder,
                ),
                eff: e,
              ),
          ]..sort((a, b) {
            final c = a.source.folderSortOrder.compareTo(
              b.source.folderSortOrder,
            );
            return c != 0 ? c : a.source.fileRef.compareTo(b.source.fileRef);
          });
      final sources = [for (final e in entries) e.source];

      // Resolve the active source: a manual override wins, but only while its
      // folder still holds the episode; otherwise fall back to priority. The
      // pin is "in effect" only when it actually selects a present source.
      var activeIdx = 0;
      String? pinnedFolder;
      final ov = overrides[key];
      if (ov != null) {
        final i = entries.indexWhere(
          (e) => e.source.folderPath == ov.folderPath,
        );
        if (i >= 0) {
          activeIdx = i;
          pinnedFolder = ov.folderPath;
        }
      }

      // Display number comes from the active source's effective match (all
      // sources are the same episode; normally identical).
      result[key] = _Logical(
        seriesId: key.$1,
        anchored: key.$2,
        displayNumber: entries[activeIdx].eff.displayNumber,
        sources: sources,
        activeFileRef: entries[activeIdx].source.fileRef,
        pinnedFolder: pinnedFolder,
      );
    });
    return result;
  }

  @override
  Future<List<Series>> allSeries() async {
    final effective = await _effectiveMatches();
    final wanted = {
      for (final e in effective)
        if (e.seriesId != null) e.seriesId!,
    };
    final byId = {for (final r in await _db.allSeriesRows()) r.seriesId: r};
    final prefs = await allPreferences();
    final externalIds = await _db.externalIdsBySeriesId();
    final list = [
      for (final id in wanted)
        if (byId[id] != null)
          _toSeries(
            byId[id]!,
            prefs[id] ?? const ShowPreferences(),
            externalIds[id] ?? ExternalIds.empty,
          ),
    ];
    // Pending (not-yet-identified) files surface as NAMED PLACEHOLDERS — one
    // per distinct parsed-title group — so the library reflects what's on disk
    // even before/without AniList. They upgrade in place once a scan matches
    // them (their rows gain an seriesId and re-group under the real series).
    final placeholderTitle = <int, String>{}; // synthetic id -> sample title
    for (final e in effective) {
      if (e.seriesId != null || !e.pending) continue;
      final raw = e.file.parsedTitle;
      if (raw.isEmpty) continue;
      placeholderTitle.putIfAbsent(
        placeholderSeriesId(normalizeTitle(raw)),
        () => raw,
      );
    }
    for (final entry in placeholderTitle.entries) {
      list.add(_placeholderSeries(entry.key, entry.value));
    }
    list.sort((a, b) => _sortTitle(a).compareTo(_sortTitle(b)));
    return list;
  }

  @override
  Future<List<Episode>> episodesFor(int seriesId) async {
    // A negative id is a pending placeholder (see [placeholderSeriesId]); its
    // "episodes" are the pending files of that parsed-title group.
    if (isPlaceholderSeriesId(seriesId)) {
      return _placeholderEpisodesFor(seriesId);
    }
    final logical = await _logicalEpisodes();
    final watch = {
      for (final w in await _db.allWatchStateRows()) (w.seriesId, w.episode): w,
    };
    final skips = <(int, int), List<SkipSourceAnswerRow>>{};
    for (final a in await _db.allSkipAnswers()) {
      (skips[(a.seriesId, a.episode)] ??= []).add(a);
    }
    final mine = [
      for (final l in logical.values)
        if (l.seriesId == seriesId) l,
    ]..sort((a, b) => (a.displayNumber ?? 0).compareTo(b.displayNumber ?? 0));
    final view = await _skipView();
    return [
      for (final l in mine)
        _toEpisode(
          l,
          watch[(seriesId, l.anchored)],
          skips[(seriesId, l.anchored)],
          view,
        ),
    ];
  }

  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async {
    final effective = await _effectiveMatches();
    final currentByFolder = await _currentFolderPaths(
      await _db.allFolderRows(),
    );
    return [
      for (final e in effective)
        // Only CONFIRMED-unmatched (AniList said no) — a pending file is shown
        // as a library placeholder instead, and must not appear here (it's
        // "not yet tried", not "couldn't identify").
        if (e.seriesId == null && !e.pending)
          IdentifiedEpisode(
            filePath: _fileRef(e.file, currentByFolder),
            parsedTitle: e.file.parsedTitle,
            parsedEpisodeNumber: e.file.episodeNumber,
            releaseGroup: e.file.releaseGroup,
            matchScore: e.file.matchScore,
          ),
    ];
  }

  /// A placeholder [Series] for a not-yet-identified parsed-title group: the
  /// parsed title stands in for the name, no art, [Series.pending] set.
  Series _placeholderSeries(int id, String parsedTitle) => Series(
    seriesId: id,
    titles: Titles(romaji: parsedTitle),
    pending: true,
  );

  /// Episodes for a pending placeholder: the not-yet-identified files of the
  /// matching parsed-title group, collapsed by episode number (so multi-source
  /// copies are one row) and resolved to their playable current path. Watch
  /// state is keyed by the placeholder's synthetic id, so resume survives until
  /// the show is identified (then re-keys to the real id on the next scan).
  Future<List<Episode>> _placeholderEpisodesFor(int placeholderId) async {
    final effective = await _effectiveMatches();
    final folders = await _db.allFolderRows();
    final folderByPath = {for (final f in folders) f.path: f};
    final currentByFolder = await _currentFolderPaths(folders);
    final watch = {
      for (final w in await _db.allWatchStateRows()) (w.seriesId, w.episode): w,
    };

    // Group this title group's pending files by episode position. A numbered
    // episode keys by its number (multi-source copies merge); an un-numbered
    // file (movie/special) keys by a stable per-file negative so distinct ones
    // stay separate rather than merging into one "Episode 0".
    final groups = <int, List<CachedFileRow>>{};
    for (final e in effective) {
      if (e.seriesId != null || !e.pending) continue;
      final raw = e.file.parsedTitle;
      if (raw.isEmpty) continue;
      if (placeholderSeriesId(normalizeTitle(raw)) != placeholderId) continue;
      final key =
          e.file.episodeNumber ??
          (-1 - placeholderStableHash(e.file.relativePath));
      groups.putIfAbsent(key, () => []).add(e.file);
    }

    final keys = groups.keys.toList()..sort();
    return [
      for (final anchored in keys)
        () {
          final sources =
              [
                for (final f in groups[anchored]!)
                  EpisodeSource(
                    fileRef: _fileRef(f, currentByFolder),
                    folderPath: f.folderPath,
                    folderSortOrder:
                        folderByPath[f.folderPath]?.sortOrder ??
                        _unfiledSortOrder,
                  ),
              ]..sort((a, b) {
                final c = a.folderSortOrder.compareTo(b.folderSortOrder);
                return c != 0 ? c : a.fileRef.compareTo(b.fileRef);
              });
          final number = anchored >= 0 ? anchored : 0;
          final w = watch[(placeholderId, anchored)];
          return Episode(
            number: number,
            fileRef: sources.first.fileRef,
            title: number > 0
                ? 'Episode $number'
                : _name(sources.first.fileRef),
            seriesId: placeholderId,
            anchoredNumber: anchored,
            watched: w?.watched ?? false,
            resumePosition: Duration(milliseconds: w?.resumePositionMs ?? 0),
            duration: Duration(milliseconds: w?.durationMs ?? 0),
            sources: sources,
          );
        }(),
    ];
  }

  /// Basename of a path (for an un-numbered placeholder episode's label).
  static String _name(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }

  // --- Watch state (keyed by episode identity, never file path) ---

  @override
  Future<void> saveProgress(
    Episode episode, {
    required Duration position,
    required Duration duration,
  }) async {
    // Progress-only write: PRESERVE the existing watched + manual-override flags
    // (never clobber a manual watched/unwatched while resume keeps ticking).
    final existing = await _db.watchStateFor(
      episode.seriesId,
      episode.anchoredNumber,
    );
    await _db.upsertWatchState(
      WatchStateRow(
        seriesId: episode.seriesId,
        episode: episode.anchoredNumber,
        resumePositionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        watched: existing?.watched ?? false,
        watchedManual: existing?.watchedManual ?? false,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> setWatched(Episode episode, {required bool watched}) async {
    final existing = await _db.watchStateFor(
      episode.seriesId,
      episode.anchoredNumber,
    );
    // The AUTO / threshold path. A MANUAL override wins: never touch a row the
    // user set by hand (the sticky watched-override is sacred user data).
    if (existing?.watchedManual ?? false) return;
    await _db.upsertWatchState(
      WatchStateRow(
        seriesId: episode.seriesId,
        episode: episode.anchoredNumber,
        // Marking watched clears resume so it leaves "Continue watching".
        resumePositionMs: watched ? 0 : (existing?.resumePositionMs ?? 0),
        durationMs: existing?.durationMs ?? episode.duration.inMilliseconds,
        watched: watched,
        watchedManual: false,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> setWatchedManual(
    Episode episode, {
    required bool watched,
  }) async {
    final existing = await _db.watchStateFor(
      episode.seriesId,
      episode.anchoredNumber,
    );
    // Sticky manual override: set watched + mark it manual so the auto/threshold
    // path leaves it alone, and it survives re-entry AND refresh/rescan (seam #5
    // — watch_state has no fill-path writer). Progress is UNTOUCHED: the saved
    // resume position + duration carry over exactly.
    await _db.upsertWatchState(
      WatchStateRow(
        seriesId: episode.seriesId,
        episode: episode.anchoredNumber,
        resumePositionMs: existing?.resumePositionMs ?? 0,
        durationMs: existing?.durationMs ?? episode.duration.inMilliseconds,
        watched: watched,
        watchedManual: true,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> clearProgress(Episode episode) =>
      _db.deleteWatchState(episode.seriesId, episode.anchoredNumber);

  @override
  Future<List<ContinueWatching>> continueWatching() async {
    final inProgress = await _db
        .inProgressWatchStates(); // ordered, recent first
    final logical = await _logicalEpisodes(); // one per episode identity
    final seriesById = {
      for (final r in await _db.allSeriesRows()) r.seriesId: r,
    };
    final skips = <(int, int), List<SkipSourceAnswerRow>>{};
    for (final a in await _db.allSkipAnswers()) {
      (skips[(a.seriesId, a.episode)] ??= []).add(a);
    }
    final prefs = await allPreferences();
    final externalIds = await _db.externalIdsBySeriesId();
    final view = await _skipView();

    final result = <ContinueWatching>[];
    for (final w in inProgress) {
      final match = logical[(w.seriesId, w.episode)];
      final series = seriesById[w.seriesId];
      if (match == null || series == null) continue; // file/series gone
      result.add(
        ContinueWatching(
          series: _toSeries(
            series,
            prefs[w.seriesId] ?? const ShowPreferences(),
            externalIds[w.seriesId] ?? ExternalIds.empty,
          ),
          episode: _toEpisode(match, w, skips[(w.seriesId, w.episode)], view),
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
  Future<void> selectSource(Episode episode, {required String folderPath}) {
    // A pending placeholder (synthetic negative id) is NOT pinnable — pinning a
    // source for an unidentified show would persist the synthetic id into
    // source_overrides and strand it on identification. Pending episodes always
    // play the automatic (highest-priority) source; this is a no-op for them.
    if (isPlaceholderSeriesId(episode.seriesId)) return Future<void>.value();
    return _db.upsertSourceOverride(
      SourceOverrideRow(
        seriesId: episode.seriesId,
        episode: episode.anchoredNumber,
        folderPath: folderPath,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> clearSource(Episode episode) {
    if (isPlaceholderSeriesId(episode.seriesId)) return Future<void>.value();
    return _db.deleteSourceOverride(episode.seriesId, episode.anchoredNumber);
  }

  // --- Missing episodes (hidden state). Sole writer of hidden_episodes;
  //     the fill path (applySync) / refreshMetadata never touch it (seam #5),
  //     so a rescan/refresh never wipes a hide. Keyed by episode identity. ---

  @override
  Future<Set<int>> hiddenEpisodes(int seriesId) async => {
    for (final h in await _db.hiddenRowsFor(seriesId)) h.episode,
  };

  @override
  Future<Map<int, Set<int>>> allHiddenEpisodes() async {
    final result = <int, Set<int>>{};
    for (final h in await _db.allHiddenRows()) {
      result.putIfAbsent(h.seriesId, () => {}).add(h.episode);
    }
    return result;
  }

  @override
  Future<void> hideEpisodes(int seriesId, List<int> episodes) =>
      _db.hideEpisodes(seriesId, episodes);

  @override
  Future<void> unhideEpisodes(int seriesId, List<int> episodes) =>
      _db.unhideEpisodes(seriesId, episodes);

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
      current.seriesId,
      current.anchoredNumber,
      logical,
    );
    if (next == null) return const NoNextEpisode();
    final w = await _db.watchStateFor(next.seriesId, next.anchored);
    final answers = await _db.skipAnswersFor(next.seriesId, next.anchored);
    return NextEpisode(_toEpisode(next, w, answers, await _skipView()));
  }

  @override
  Future<Map<int, Episode>> upNextBySeries() async {
    final logical = await _logicalEpisodes();
    final watch = {
      for (final w in await _db.allWatchStateRows()) (w.seriesId, w.episode): w,
    };
    final skips = <(int, int), List<SkipSourceAnswerRow>>{};
    for (final a in await _db.allSkipAnswers()) {
      (skips[(a.seriesId, a.episode)] ??= []).add(a);
    }

    // Furthest WATCHED anchored position per series the user has started.
    final latestWatched = <int, int>{};
    for (final w in watch.values) {
      if (!w.watched) continue;
      final cur = latestWatched[w.seriesId];
      if (cur == null || w.episode > cur) {
        latestWatched[w.seriesId] = w.episode;
      }
    }

    final result = <int, Episode>{};
    final view = await _skipView();
    latestWatched.forEach((seriesId, anchored) {
      // Same resolver as nextEpisode — within-season next.
      final next = _resolveNext(seriesId, anchored, logical);
      if (next == null) return; // NoNextEpisode -> caught up, show nothing
      final w = watch[(next.seriesId, next.anchored)];
      if (w?.watched ?? false) return; // already watched -> nothing "next"
      result[seriesId] = _toEpisode(
        next,
        w,
        skips[(next.seriesId, next.anchored)],
        view,
      );
    });
    return result;
  }

  /// The logical episode after (seriesId, anchored) WITHIN the same series, or
  /// null at the season boundary (the series' last in-library episode). The
  /// null is the seam where cross-season will later follow the SEQUEL relation.
  _Logical? _resolveNext(
    int seriesId,
    int anchored,
    Map<(int, int), _Logical> logical,
  ) => logical[(seriesId, anchored + 1)];

  /// Everything the READ path needs to turn stored answers into skip windows.
  ///
  /// All three are wired AFTER construction because the settings repository is
  /// built FROM this one (it delegates show-preferences here), so the two
  /// cannot both be constructor arguments. Null until wired, and the nulls
  /// degrade to "no filter, built-in order, no cross-checking".
  ///
  /// [loadActiveSkipSources] yields the enabled source TOKENS in priority
  /// order. The composition root supplies it because only it knows which
  /// sources this build ships; the repository must not see a provider (seam
  /// #1). A source absent from that list is one the user switched off, and its
  /// stored answers stop being used the moment they do — no refresh.
  Future<Duration> Function()? loadMinSkipLength;
  Future<List<String>> Function()? loadActiveSkipSources;
  Future<bool> Function()? loadCorroborateSkips;

  /// Read fresh per query, never snapshotted, so changing any of these takes
  /// effect on the next read instead of needing a rescan.
  Future<({Duration floor, List<String> order, bool corroborate})>
  _skipView() async => (
    floor: await loadMinSkipLength?.call() ?? Duration.zero,
    order: await loadActiveSkipSources?.call() ?? const <String>[],
    corroborate: await loadCorroborateSkips?.call() ?? false,
  );

  Episode _toEpisode(
    _Logical l,
    WatchStateRow? w,
    List<SkipSourceAnswerRow>? answers,
    ({Duration floor, List<String> order, bool corroborate}) view,
  ) {
    // Resolved HERE, not at write time. Order picks the times, cross-checking
    // picks the verdict, the floor filters — so all three take effect at once
    // across the whole library, and none of it is a stored value that could go
    // stale when its rule changes.
    final resolved = resolveEpisodeSkips(
      [
        for (final a in answers ?? const <SkipSourceAnswerRow>[])
          SourceAnswer(
            source: a.source,
            intro: _range(a.introStartMs, a.introEndMs),
            outro: _range(a.outroStartMs, a.outroEndMs),
          ),
      ],
      sourceOrder: view.order,
      corroborate: view.corroborate,
    );
    return Episode(
      number: l.displayNumber ?? 0,
      fileRef: l.activeFileRef,
      title: l.displayNumber != null ? 'Episode ${l.displayNumber}' : null,
      seriesId: l.seriesId,
      anchoredNumber: l.anchored,
      watched: w?.watched ?? false,
      resumePosition: Duration(milliseconds: w?.resumePositionMs ?? 0),
      duration: Duration(milliseconds: w?.durationMs ?? 0),
      sources: l.sources,
      pinnedSourceFolder: l.pinnedFolder,
      introSkip: dropIfShorterThan(resolved.intro?.range, view.floor),
      outroSkip: dropIfShorterThan(resolved.outro?.range, view.floor),
      introConfidence: resolved.intro?.confidence ?? SkipConfidence.single,
      outroConfidence: resolved.outro?.confidence ?? SkipConfidence.single,
    );
  }

  /// Build a [SkipRange] when both bounds are present, else null.
  SkipRange? _range(int? startMs, int? endMs) =>
      (startMs != null && endMs != null)
      ? SkipRange(
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: endMs),
        )
      : null;

  Series _toSeries(
    CachedSeriesRow r, [
    ShowPreferences prefs = const ShowPreferences(),
    ExternalIds externalIds = ExternalIds.empty,
  ]) => Series(
    seriesId: r.seriesId,
    externalIds: externalIds,
    titles: Titles(romaji: r.romaji, english: r.english, native: r.nativeTitle),
    format: r.format,
    episodeCount: r.episodeCount,
    // The LOCAL art path, so offline browse shows art (not the remote URL).
    coverImageRef: r.coverImagePath,
    // Per-show prefs surfaced onto the projection so every cover site + the
    // card's Next button render consistently (the store stays the source).
    pictureMode: prefs.pictureMode,
    nextEpisodeHidden: prefs.nextEpisodeHidden,
  );

  ShowPreferences _toPrefs(ShowPreferenceRow? r) => ShowPreferences(
    pictureMode: PictureMode.fromToken(r?.pictureMode),
    nextEpisodeHidden: r?.nextEpisodeHidden ?? false,
  );

  // --- Per-show preferences (ShowPreferencesRepository). Sacred: no fill-path
  //     writer, so refresh/rescan can't wipe these. ---

  @override
  Future<ShowPreferences> preferencesFor(int seriesId) async =>
      _toPrefs(await _db.showPrefFor(seriesId));

  @override
  Future<Map<int, ShowPreferences>> allPreferences() async => {
    for (final r in await _db.allShowPrefRows()) r.seriesId: _toPrefs(r),
  };

  @override
  Future<void> setPictureMode(int seriesId, PictureMode mode) async {
    final existing = await _db.showPrefFor(seriesId);
    await _db.upsertShowPref(
      ShowPreferenceRow(
        seriesId: seriesId,
        pictureMode: mode.token,
        nextEpisodeHidden: existing?.nextEpisodeHidden ?? false,
      ),
    );
  }

  @override
  Future<void> setNextEpisodeHidden(
    int seriesId, {
    required bool hidden,
  }) async {
    final existing = await _db.showPrefFor(seriesId);
    await _db.upsertShowPref(
      ShowPreferenceRow(
        seriesId: seriesId,
        pictureMode: existing?.pictureMode ?? PictureMode.normal.token,
        nextEpisodeHidden: hidden,
      ),
    );
  }

  @override
  Future<void> setAllNextEpisodeHidden({required bool hidden}) async {
    // Overwrite every cached show's flag, preserving each show's picture mode.
    final existing = {
      for (final r in await _db.allShowPrefRows()) r.seriesId: r,
    };
    for (final s in await _db.allSeriesRows()) {
      await _db.upsertShowPref(
        ShowPreferenceRow(
          seriesId: s.seriesId,
          pictureMode:
              existing[s.seriesId]?.pictureMode ?? PictureMode.normal.token,
          nextEpisodeHidden: hidden,
        ),
      );
    }
  }

  // Sort key = the same display title, lowercased. The empty-string fallback
  // this used to carry only differed for an all-null-title series (unreachable —
  // every real entry has ≥1 title, and a pending placeholder carries its parsed
  // title in romaji), so routing through displayTitle keeps one source with no
  // observable sort change.
  String _sortTitle(Series s) => s.displayTitle.toLowerCase();
}
