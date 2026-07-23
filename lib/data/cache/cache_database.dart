import 'package:drift/drift.dart';

import '../folders/volume_resolver.dart' show rebaseToFolderRelative;

part 'cache_database.g.dart';

/// AniList metadata projection, keyed by AniList ID. ONLY fields the UI renders
/// (seam rule: a projection, not a clone). `coverImagePath` is the downloaded
/// local art file so offline browse shows art, not broken images.
@DataClassName('CachedSeriesRow')
class SeriesCache extends Table {
  IntColumn get anilistId => integer()();

  /// MyAnimeList id (AniList `idMal`) — the key AniSkip needs. Nullable: not
  /// every entry has a MAL mapping, and pre-v8 rows backfill on re-fetch.
  IntColumn get idMal => integer().nullable()();

  TextColumn get romaji => text().nullable()();
  TextColumn get english => text().nullable()();
  TextColumn get nativeTitle => text().nullable()();
  TextColumn get format => text().nullable()();
  IntColumn get episodeCount => integer().nullable()();
  TextColumn get coverImageUrl => text().nullable()();
  TextColumn get coverImagePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {anilistId};

  @override
  String get tableName => 'series_cache';
}

/// One scanned video file. Identity is its LOCATION — [folderPath] (the owning
/// library folder's stable identity) + [relativePath] (the path within that
/// folder) — NOT an absolute mount path. This is what keeps identity stable when
/// a removable/network volume remounts under a different `/Volumes` name: the
/// folder is re-found by its volume UUID (see [LibraryFolders.volumeId]) and the
/// relative paths still resolve, so a remount does NOT churn the cache (no
/// re-identify, no AniList refetch). [fileSize] + [modifiedAtMs] remain the
/// "unchanged" key for incremental rescans. A null [anilistId] is a
/// known-unmatched file — it persists across rescans (Stage 5 fixes it).
@DataClassName('CachedFileRow')
class FileCache extends Table {
  TextColumn get folderPath => text()();
  TextColumn get relativePath => text()();
  IntColumn get fileSize => integer()();
  IntColumn get modifiedAtMs => integer()();
  IntColumn get anilistId => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();
  TextColumn get parsedTitle => text()();
  RealColumn get matchScore => real().withDefault(const Constant(0))();
  TextColumn get releaseGroup => text().nullable()();

  /// Identification lifecycle, meaningful ONLY while [anilistId] is null. This
  /// is the THIRD state (besides matched / confirmed-unmatched): true = PENDING
  /// — the file was discovered on disk and parsed, but AniList hasn't yet
  /// resolved it (offline, not-yet-tried, or a transient lookup failure). A
  /// pending row is shown in the library as a NAMED PLACEHOLDER (parsed title,
  /// no art), is RETRIED on every scan, and upgrades in place to a match when
  /// AniList succeeds. false (the default) = CONFIRMED-UNMATCHED — AniList was
  /// consulted and genuinely found nothing (or the file has no parseable
  /// title); it goes to the fix-match "unmatched" screen, not the grid.
  ///
  /// Defaulting to false makes the v9->v10 migration exact: every pre-v10
  /// unmatched row keeps its old meaning (confirmed-unmatched), and matched
  /// rows are unaffected (the flag is ignored when [anilistId] is set).
  BoolColumn get pendingIdentification =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {folderPath, relativePath};

  @override
  String get tableName => 'file_cache';
}

/// User-added library folders (Stage 5). Identity is the folder [path], which
/// for protected locations must have originated from a native open-panel pick
/// (its inferred-consent `com.apple.macl` grant is what survives relaunch).
@DataClassName('LibraryFolderRow')
class LibraryFolders extends Table {
  TextColumn get path => text()();
  IntColumn get addedAtMs => integer()();

  /// User-controllable rank (lower = higher priority). Drives multi-source
  /// priority: top = preferred default playback source. Set by drag-to-reorder
  /// in the folders screen (see [reorderFolders]); stable across relaunch.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Stable volume identity (a volume UUID) for a folder on a removable/network
  /// volume, so the folder is re-found after its volume remounts under a
  /// different `/Volumes` name. Null for internal-disk folders (their absolute
  /// path is already stable) and for not-yet-bound folders (backfilled on the
  /// next scan while the volume is mounted). Used WITH [volumeSubpath].
  TextColumn get volumeId => text().nullable()();

  /// The folder's path WITHIN its volume (e.g. `shows/anime`; `''` = the volume
  /// root). Joined onto the volume's current mount point to reconstruct the
  /// folder's current absolute path after a remount. Null when [volumeId] is.
  TextColumn get volumeSubpath => text().nullable()();

  @override
  Set<Column> get primaryKey => {path};

  @override
  String get tableName => 'library_folders';
}

/// User match corrections (Stage 5 fix-match). A SEPARATE authoritative store
/// that the auto-matcher (LibrarySync) structurally cannot write to — seam #5
/// is enforced by there being no write path from the rescan into this table.
///
/// Keyed by content fingerprint `(fileSize, modifiedAtMs)`, NOT path, so an
/// override follows a file across a move/rename without the sync ever touching
/// this table. (Distinct real media don't share a byte-exact size + mtime.)
///
/// [anchoredEpisode] is the episode position WITHIN [anilistId] (file "12" of a
/// continuously-numbered show = Season-2-entry episode 1). The displayed number
/// is derived: `displayContinuous ? anchoredEpisode + continuousOffset
/// : anchoredEpisode`, where [continuousOffset] is the real prior-season episode
/// count captured at assign time (never hardcoded).
@DataClassName('MatchOverrideRow')
class MatchOverrides extends Table {
  IntColumn get fileSize => integer()();
  IntColumn get modifiedAtMs => integer()();
  IntColumn get anilistId => integer()();
  IntColumn get anchoredEpisode => integer().nullable()();
  IntColumn get continuousOffset => integer().withDefault(const Constant(0))();
  BoolColumn get displayContinuous =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {fileSize, modifiedAtMs};

  @override
  String get tableName => 'match_overrides';
}

/// Local watch state (Stage 6). Keyed by EPISODE IDENTITY — [anilistId] + the
/// anchored (AniList-faithful) [episode] position — NOT by file path or player
/// session. This is what survives a file move and what the future multi-source
/// stage needs: "resume episode 5" is episode 5 whatever file played it.
@DataClassName('WatchStateRow')
class WatchStates extends Table {
  IntColumn get anilistId => integer()();
  IntColumn get episode => integer()();
  IntColumn get resumePositionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get watched => boolean().withDefault(const Constant(false))();

  /// True when [watched] was set by a MANUAL toggle (the sticky per-episode
  /// override) rather than derived from the watched-threshold during playback.
  /// A manual override wins over the threshold: the auto path won't touch a row
  /// with this set, and it survives refresh/rescan (watch_state is never in the
  /// fill path — seam #5). false = the [watched] value is threshold-derived.
  BoolColumn get watchedManual =>
      boolean().withDefault(const Constant(false))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {anilistId, episode};

  @override
  String get tableName => 'watch_state';
}

/// Manual SOURCE override (multi-source episodes). One logical episode = the
/// files sharing an episode identity `(anilistId, anchored episode)` across
/// library folders; by default it plays from the highest-priority folder
/// (lowest `library_folders.sortOrder`) that has it. This table pins a specific
/// source instead — keyed by that SAME episode identity (so it is shared across
/// every file of the episode), storing the chosen library [folderPath].
///
/// Sacred across rescans (seam #5, source dimension): the auto path (LibrarySync
/// → applySync) never writes this table, so a rescan cannot clobber the choice —
/// even if a higher-priority folder later gains the episode. If the chosen
/// folder no longer holds the episode, resolution falls back to folder priority
/// and the row sits inert (re-applies if that folder returns).
@DataClassName('SourceOverrideRow')
class SourceOverrides extends Table {
  IntColumn get anilistId => integer()();
  IntColumn get episode => integer()();
  TextColumn get folderPath => text()();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {anilistId, episode};

  @override
  String get tableName => 'source_overrides';
}

/// Cached OP/ED skip windows (the auto-skip feature). Fetched from AniSkip at
/// scan time and read OFFLINE during playback — the player never hits the
/// network. Keyed by EPISODE IDENTITY ([anilistId] + the anchored [episode]
/// position), consistent with watch_state / source_overrides. A row exists only
/// when AniSkip had data; absence = no skip affordance (partial coverage is
/// normal). Either window may be null (intro-only or outro-only). Times are ms
/// from the start of the file.
@DataClassName('SkipSegmentRow')
class SkipSegments extends Table {
  IntColumn get anilistId => integer()();
  IntColumn get episode => integer()();
  IntColumn get introStartMs => integer().nullable()();
  IntColumn get introEndMs => integer().nullable()();
  IntColumn get outroStartMs => integer().nullable()();
  IntColumn get outroEndMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {anilistId, episode};

  @override
  String get tableName => 'skip_segments';
}

/// User-hidden MISSING episodes (the missing-episodes feature). Keyed by EPISODE
/// IDENTITY ([anilistId] + the anchored [episode] position), consistent with
/// watch_state / source_overrides / skip_segments. A hidden episode is removed
/// from the show's episode list (no ghost tile) and excluded from completeness
/// counts. Hiding is always per-episode, even when the action targets a bundle.
///
/// SACRED (seam #5): the auto fill path (LibrarySync → applySync) and
/// refreshMetadata have NO write path to this table, so a rescan / metadata
/// refresh never wipes hidden state — it is persisted user data, like a
/// fix-match or a source pin. The only writers are the hide/unhide UI actions.
@DataClassName('HiddenEpisodeRow')
class HiddenEpisodes extends Table {
  IntColumn get anilistId => integer()();
  IntColumn get episode => integer()();
  IntColumn get hiddenAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {anilistId, episode};

  @override
  String get tableName => 'hidden_episodes';
}

/// App preferences (key/value). NOT part of the AniList projection — a small
/// local store for UI choices like the collapsed "Continue watching" section.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'app_settings';
}

/// PER-SHOW preferences, keyed by show identity ([anilistId]). Sacred user data:
/// written ONLY by the per-show menu actions; the fill path (applySync) and
/// refreshMetadata never touch it, so a rescan/refresh can't wipe it (seam #5) —
/// like watch_state / source_overrides / hidden_episodes. Extensible: a new
/// per-show pref is a new column here + a field on the domain ShowPreferences,
/// NOT a parallel store. Absent row = all defaults.
@DataClassName('ShowPreferenceRow')
class ShowPrefs extends Table {
  IntColumn get anilistId => integer()();

  /// Cover display mode token (see PictureMode): 'normal' / 'blur' / 'removed'.
  TextColumn get pictureMode => text().withDefault(const Constant('normal'))();

  /// Whether the card's "Next episode" button is hidden for this show.
  BoolColumn get nextEpisodeHidden =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {anilistId};

  @override
  String get tableName => 'show_preferences';
}

@DriftDatabase(
  tables: [
    SeriesCache,
    FileCache,
    LibraryFolders,
    MatchOverrides,
    WatchStates,
    SourceOverrides,
    SkipSegments,
    HiddenEpisodes,
    AppSettings,
    ShowPrefs,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.e);

  @override
  int get schemaVersion => 13;

  // Migrations are set up deliberately (seam rule: a schema change is a real
  // migration). v2 library_folders; v3 match_overrides; v4 folder sort order;
  // v5 watch_state; v6 app_settings; v7 source_overrides; v8 series_cache.idMal
  // + skip_segments (auto-skip); v9 stable volume identity — file_cache keyed by
  // (folder_path, relative_path) instead of an absolute path, + library_folders
  // volume binding (see [_migrateFileCacheToRelativeV9]); v10 file_cache
  // .pending_identification — the "discovered but not yet identified" state for
  // immediate library population (an additive column, default 0 = preserves
  // every existing row's meaning); v11 hidden_episodes — user-hidden missing
  // episodes (a brand-new table, so existing populated caches are untouched);
  // v12 watch_state.watched_manual — the sticky manual watched-override flag (an
  // additive column, default 0, so existing rows stay threshold-derived); v13
  // show_preferences — per-show prefs (cover display mode + hide-next-episode),
  // a brand-new table so existing populated caches are untouched.
  //
  // v8 RECLAIMED: it was briefly scratch on an unshipped branch (series_relations,
  // the "Up Next" overshoot) then reverted — it never reached main and no DB sits
  // at 8 (drift normalized the one dev cache that touched it back to 7), so the
  // number was free. This v8 adds idMal + skip_segments, NOT series_relations, so
  // there's no clash even with a backup-restored cache carrying the orphan table.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(libraryFolders);
      }
      if (from < 3) {
        await m.createTable(matchOverrides);
      }
      if (from < 4) {
        await m.addColumn(libraryFolders, libraryFolders.sortOrder);
        // Backfill existing rows so their order reflects add time.
        await customStatement(
          'UPDATE library_folders SET sort_order = added_at_ms',
        );
      }
      if (from < 5) {
        await m.createTable(watchStates);
      }
      if (from < 6) {
        await m.createTable(appSettings);
      }
      if (from < 7) {
        await m.createTable(sourceOverrides);
      }
      if (from < 8) {
        await m.addColumn(seriesCache, seriesCache.idMal);
        await m.createTable(skipSegments);
      }
      if (from < 9) {
        await m.addColumn(libraryFolders, libraryFolders.volumeId);
        await m.addColumn(libraryFolders, libraryFolders.volumeSubpath);
        await _migrateFileCacheToRelativeV9(m);
      }
      if (from >= 9 && from < 10) {
        // Additive: existing rows default to 0 (pending = false), so every
        // already-cached unmatched file stays "confirmed-unmatched" (its
        // pre-v10 meaning) and matched files are untouched. New pending rows
        // are written only by go-forward scans.
        //
        // Guarded `from >= 9` deliberately: a from-<9 upgrade RECREATES
        // file_cache via createTable in the v9 step above, which already builds
        // the current shape (with pending_identification), so adding it again
        // here would be a duplicate-column error. Only a cache that was already
        // at v9 (real column-less file_cache) needs the addColumn.
        await m.addColumn(fileCache, fileCache.pendingIdentification);
      }
      if (from < 11) {
        // Brand-new table for the missing-episodes feature; a from-<11 upgrade
        // just creates it empty, so every existing populated cache is
        // unaffected (no shows have hidden episodes until the user hides one).
        await m.createTable(hiddenEpisodes);
      }
      if (from < 12) {
        // Additive: the manual watched-override flag. Existing rows default to
        // 0 (false) → their `watched` value keeps its threshold-derived meaning,
        // so a populated cache is untouched and nothing is retroactively "manual".
        await m.addColumn(watchStates, watchStates.watchedManual);
      }
      if (from < 13) {
        // Brand-new per-show preferences table; a from-<13 upgrade just creates
        // it empty, so every existing populated cache is unaffected (no show has
        // an override until the user sets one).
        await m.createTable(showPrefs);
      }
    },
  );

  /// v9: move file_cache identity from an absolute `path` to (folder_path,
  /// relative_path). Rebase every existing row IN PLACE by stripping its owning
  /// library folder's prefix — PURE STRING work (folder paths == file prefixes
  /// at migration time, before anything has remounted), so identity is
  /// PRESERVED and the first post-migration rescan sees every file unchanged (no
  /// re-identify, no AniList refetch). Watch-state / overrides aren't touched
  /// (they're fingerprint/identity keyed). Volume UUIDs are NOT resolved here
  /// (that needs diskutil + a mounted volume) — they backfill on the next scan.
  Future<void> _migrateFileCacheToRelativeV9(Migrator m) async {
    final folderRows = await customSelect(
      'SELECT path FROM library_folders',
    ).get();
    final folderPaths = [for (final r in folderRows) r.read<String>('path')];
    final oldFiles = await customSelect('SELECT * FROM file_cache').get();

    // Rebuild the table under the new (folder_path, relative_path) PK, copying
    // each row rebased. Rename-create-copy-drop is the SQLite idiom for a PK
    // change; the whole onUpgrade runs in drift's migration transaction.
    await customStatement('ALTER TABLE file_cache RENAME TO _file_cache_v8');
    await m.createTable(fileCache);
    for (final r in oldFiles) {
      final loc = rebaseToFolderRelative(r.read<String>('path'), folderPaths);
      await customStatement(
        'INSERT INTO file_cache (folder_path, relative_path, file_size, '
        'modified_at_ms, anilist_id, episode_number, parsed_title, '
        'match_score, release_group) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          loc.folderPath,
          loc.relativePath,
          r.read<int>('file_size'),
          r.read<int>('modified_at_ms'),
          r.readNullable<int>('anilist_id'),
          r.readNullable<int>('episode_number'),
          r.read<String>('parsed_title'),
          r.read<double>('match_score'),
          r.readNullable<String>('release_group'),
        ],
      );
    }
    await customStatement('DROP TABLE _file_cache_v8');
  }

  // --- Read path (used by DriftLibraryRepository) ---

  Future<List<CachedSeriesRow>> allSeriesRows() => select(seriesCache).get();

  Future<List<CachedFileRow>> filesForSeries(int anilistId) =>
      (select(fileCache)..where((f) => f.anilistId.equals(anilistId))).get();

  Future<List<CachedFileRow>> unmatchedFileRows() =>
      (select(fileCache)..where((f) => f.anilistId.isNull())).get();

  // --- Library folders (Stage 5) ---

  Future<List<LibraryFolderRow>> allFolderRows() => (select(
    libraryFolders,
  )..orderBy([(f) => OrderingTerm(expression: f.sortOrder)])).get();

  /// Append a folder to the end of the priority order (highest sortOrder + 1).
  Future<void> insertFolder(String path) async {
    final existing = await allFolderRows();
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((r) => r.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await into(libraryFolders).insertOnConflictUpdate(
      LibraryFolderRow(
        path: path,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
        sortOrder: nextOrder,
      ),
    );
  }

  /// Persist a new priority order: sortOrder = position in [pathsInOrder]
  /// (index 0 = highest priority). Re-bases all ranks to 0..n-1 atomically, so
  /// a later [insertFolder] still appends at the end. Touches ONLY sortOrder —
  /// no file or override row is affected, so source resolution simply re-reads
  /// the new order on the next query (no rescan needed).
  Future<void> reorderFolders(List<String> pathsInOrder) {
    return transaction(() async {
      for (var i = 0; i < pathsInOrder.length; i++) {
        await (update(libraryFolders)
              ..where((f) => f.path.equals(pathsInOrder[i])))
            .write(LibraryFoldersCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<void> deleteFolder(String path) =>
      (delete(libraryFolders)..where((f) => f.path.equals(path))).go();

  /// Remove a folder and the files under it, then prune orphaned series — all
  /// atomically (so the cache stays consistent immediately, without a rescan).
  /// Files are keyed by their owning folder, so removal is an exact match on
  /// [folderPath] (no path-prefix scan).
  Future<void> removeFolderAndFiles(String path) {
    return transaction(() async {
      await (delete(libraryFolders)..where((f) => f.path.equals(path))).go();
      await (delete(fileCache)..where((f) => f.folderPath.equals(path))).go();
      await customStatement(
        'DELETE FROM series_cache WHERE anilist_id NOT IN ('
        'SELECT anilist_id FROM file_cache WHERE anilist_id IS NOT NULL '
        'UNION SELECT anilist_id FROM match_overrides)',
      );
    });
  }

  /// Record a folder's volume binding (UUID + within-volume subpath), discovered
  /// at scan/add time while the volume is mounted. Touches only these columns,
  /// so it never disturbs sortOrder or any other folder state.
  Future<void> bindFolderVolume(
    String path,
    String volumeId,
    String volumeSubpath,
  ) => (update(libraryFolders)..where((f) => f.path.equals(path))).write(
    LibraryFoldersCompanion(
      volumeId: Value(volumeId),
      volumeSubpath: Value(volumeSubpath),
    ),
  );

  // --- Match overrides (Stage 5 fix-match). Written ONLY by FixMatchService;
  //     LibrarySync has no reference to these methods (seam #5 by structure). ---

  Future<List<MatchOverrideRow>> allOverrideRows() =>
      select(matchOverrides).get();

  /// Find a cached file by its content fingerprint (size + mtime). Used by
  /// fix-match, which stats the present file — so it needs no path scheme at all
  /// and works unchanged across moves/remounts. (Distinct real media don't share
  /// a byte-exact size + mtime; multi-source copies of one episode that happen
  /// to collide resolve to the same episode anyway.)
  Future<CachedFileRow?> fileByFingerprint(int fileSize, int modifiedAtMs) =>
      (select(fileCache)
            ..where(
              (f) =>
                  f.fileSize.equals(fileSize) &
                  f.modifiedAtMs.equals(modifiedAtMs),
            )
            ..limit(1))
          .getSingleOrNull();

  /// Cache a series without pruning (used by fix-match before its override
  /// row exists — applySync's prune would otherwise drop the new series).
  Future<void> upsertSeries(CachedSeriesRow row) =>
      into(seriesCache).insertOnConflictUpdate(row);

  Future<void> upsertOverride(MatchOverrideRow row) =>
      into(matchOverrides).insertOnConflictUpdate(row);

  Future<void> deleteOverride(int fileSize, int modifiedAtMs) =>
      (delete(matchOverrides)..where(
            (o) =>
                o.fileSize.equals(fileSize) &
                o.modifiedAtMs.equals(modifiedAtMs),
          ))
          .go();

  // --- Watch state (Stage 6). Keyed by episode identity (anilistId, episode). ---

  Future<List<WatchStateRow>> allWatchStateRows() => select(watchStates).get();

  /// In-progress episodes: a saved resume position and not yet watched,
  /// most-recently-updated first (for the "Continue watching" row).
  Future<List<WatchStateRow>> inProgressWatchStates() =>
      (select(watchStates)
            ..where(
              (w) =>
                  w.resumePositionMs.isBiggerThanValue(0) &
                  w.watched.equals(false),
            )
            ..orderBy([
              (w) => OrderingTerm(
                expression: w.updatedAtMs,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<WatchStateRow?> watchStateFor(int anilistId, int episode) =>
      (select(watchStates)..where(
            (w) => w.anilistId.equals(anilistId) & w.episode.equals(episode),
          ))
          .getSingleOrNull();

  Future<void> upsertWatchState(WatchStateRow row) =>
      into(watchStates).insertOnConflictUpdate(row);

  /// Remove an episode's watch state entirely (dismiss from "Continue
  /// watching" without marking it watched).
  Future<void> deleteWatchState(int anilistId, int episode) =>
      (delete(watchStates)..where(
            (w) => w.anilistId.equals(anilistId) & w.episode.equals(episode),
          ))
          .go();

  // --- Source overrides (multi-source). Written ONLY by the source-selection
  //     path; LibrarySync's fill path (applySync) never touches this table, so
  //     a rescan cannot clobber a manual source choice (seam #5). ---

  Future<List<SourceOverrideRow>> allSourceOverrideRows() =>
      select(sourceOverrides).get();

  Future<void> upsertSourceOverride(SourceOverrideRow row) =>
      into(sourceOverrides).insertOnConflictUpdate(row);

  Future<void> deleteSourceOverride(int anilistId, int episode) =>
      (delete(sourceOverrides)..where(
            (s) => s.anilistId.equals(anilistId) & s.episode.equals(episode),
          ))
          .go();

  // --- Skip segments (auto-skip). Filled at scan time from AniSkip; read
  //     offline during playback. ---

  Future<List<SkipSegmentRow>> allSkipRows() => select(skipSegments).get();

  Future<SkipSegmentRow?> skipSegmentFor(int anilistId, int episode) =>
      (select(skipSegments)..where(
            (s) => s.anilistId.equals(anilistId) & s.episode.equals(episode),
          ))
          .getSingleOrNull();

  /// Upsert one skip row directly (the refresh-metadata backfill — no pruning,
  /// so fix-matches / watch-state are untouched).
  Future<void> upsertSkipSegment(SkipSegmentRow row) =>
      into(skipSegments).insertOnConflictUpdate(row);

  // --- Hidden episodes (missing-episodes feature). Written ONLY by the
  //     hide/unhide UI actions; the fill path (applySync) and refreshMetadata
  //     never touch this table, so a rescan/refresh can't wipe it (seam #5). ---

  Future<List<HiddenEpisodeRow>> allHiddenRows() =>
      select(hiddenEpisodes).get();

  Future<List<HiddenEpisodeRow>> hiddenRowsFor(int anilistId) => (select(
    hiddenEpisodes,
  )..where((h) => h.anilistId.equals(anilistId))).get();

  /// Hide a set of episode positions for one series (per-episode, even when the
  /// hide action targeted a bundle). Idempotent upserts in one transaction.
  Future<void> hideEpisodes(int anilistId, List<int> episodes) => transaction(
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final ep in episodes) {
        await into(hiddenEpisodes).insertOnConflictUpdate(
          HiddenEpisodeRow(anilistId: anilistId, episode: ep, hiddenAtMs: now),
        );
      }
    },
  );

  /// Unhide a set of episode positions for one series.
  Future<void> unhideEpisodes(int anilistId, List<int> episodes) =>
      transaction(() async {
        for (final ep in episodes) {
          await (delete(hiddenEpisodes)..where(
                (h) => h.anilistId.equals(anilistId) & h.episode.equals(ep),
              ))
              .go();
        }
      });

  // --- App settings (key/value preferences) ---

  Future<String?> getSetting(String key) => (select(
    appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull().then((r) => r?.value);

  Future<void> setSetting(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingRow(key: key, value: value));

  // --- Per-show preferences. Written ONLY by the per-show menu actions; the
  //     fill path (applySync) + refreshMetadata never touch this table, so a
  //     rescan/refresh can't wipe a preference (seam #5). ---

  Future<List<ShowPreferenceRow>> allShowPrefRows() => select(showPrefs).get();

  Future<ShowPreferenceRow?> showPrefFor(int anilistId) => (select(
    showPrefs,
  )..where((p) => p.anilistId.equals(anilistId))).getSingleOrNull();

  Future<void> upsertShowPref(ShowPreferenceRow row) =>
      into(showPrefs).insertOnConflictUpdate(row);

  // --- Fill path (used by LibrarySync) ---

  Future<List<CachedFileRow>> allFileRows() => select(fileCache).get();

  /// Write rows to file_cache up front, in one transaction, with NO pruning or
  /// series writes. This is the immediate-population "phase 1": newly-seen
  /// files land as PENDING placeholders so the library shows them before
  /// identification runs (which may be slow, or fail, or be offline). Upserts,
  /// so a re-scan that re-discovers the same file is idempotent.
  Future<void> upsertFiles(List<CachedFileRow> rows) => transaction(() async {
    for (final r in rows) {
      await into(fileCache).insertOnConflictUpdate(r);
    }
  });

  /// Apply a computed delta atomically: never half-write a record. Upserts
  /// series + files (+ any freshly-fetched skip windows), deletes removed
  /// files (by their (folderPath, relativePath) identity), then prunes series
  /// with no files and now-orphaned skip rows.
  ///
  /// [promotions] carry `(placeholderId -> realAniListId)` for shows that just
  /// went from pending to identified this scan. For each, watch_state rows
  /// recorded against the synthetic placeholder id (you watched the show before
  /// it was identified) are REKEYED to the real id — so resume progress carries
  /// over to the real series instead of being stranded. Only real episode
  /// positions (>= 0) move; any leftover placeholder-keyed rows are then
  /// deleted, so no synthetic id survives identification. `UPDATE OR IGNORE`
  /// leaves a pre-existing real row (already-watched-as-matched) untouched.
  Future<void> applySync({
    required List<CachedSeriesRow> seriesUpserts,
    required List<CachedFileRow> fileUpserts,
    required List<(String folderPath, String relativePath)> removedKeys,
    List<SkipSegmentRow> skipUpserts = const [],
    List<(int placeholderId, int realId)> promotions = const [],
  }) {
    return transaction(() async {
      for (final s in seriesUpserts) {
        await into(seriesCache).insertOnConflictUpdate(s);
      }
      for (final f in fileUpserts) {
        await into(fileCache).insertOnConflictUpdate(f);
      }
      for (final s in skipUpserts) {
        await into(skipSegments).insertOnConflictUpdate(s);
      }
      for (final (placeholderId, realId) in promotions) {
        await customStatement(
          'UPDATE OR IGNORE watch_state SET anilist_id = ? '
          'WHERE anilist_id = ? AND episode >= 0',
          [realId, placeholderId],
        );
        await customStatement('DELETE FROM watch_state WHERE anilist_id = ?', [
          placeholderId,
        ]);
      }
      for (final k in removedKeys) {
        await (delete(fileCache)..where(
              (f) => f.folderPath.equals(k.$1) & f.relativePath.equals(k.$2),
            ))
            .go();
      }
      await customStatement(
        'DELETE FROM series_cache WHERE anilist_id NOT IN ('
        'SELECT anilist_id FROM file_cache WHERE anilist_id IS NOT NULL '
        'UNION SELECT anilist_id FROM match_overrides)',
      );
      // Drop skip rows whose series is no longer cached.
      await customStatement(
        'DELETE FROM skip_segments WHERE anilist_id NOT IN ('
        'SELECT anilist_id FROM series_cache)',
      );
    });
  }
}
