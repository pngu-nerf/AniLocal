import 'package:drift/drift.dart';

part 'cache_database.g.dart';

/// AniList metadata projection, keyed by AniList ID. ONLY fields the UI renders
/// (seam rule: a projection, not a clone). `coverImagePath` is the downloaded
/// local art file so offline browse shows art, not broken images.
@DataClassName('CachedSeriesRow')
class SeriesCache extends Table {
  IntColumn get anilistId => integer()();
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

/// One scanned video file. Identity is [path]. [fileSize] + [modifiedAtMs] are
/// the "unchanged" key for incremental rescans. A null [anilistId] means a
/// known-unmatched file — it persists across rescans (Stage 5 fixes it), it
/// does not vanish.
@DataClassName('CachedFileRow')
class FileCache extends Table {
  TextColumn get path => text()();
  IntColumn get fileSize => integer()();
  IntColumn get modifiedAtMs => integer()();
  IntColumn get anilistId => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();
  TextColumn get parsedTitle => text()();
  RealColumn get matchScore => real().withDefault(const Constant(0))();
  TextColumn get releaseGroup => text().nullable()();

  @override
  Set<Column> get primaryKey => {path};

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

  /// User-controllable rank (lower = higher priority). Stored so the order is
  /// stable across relaunch and expresses "A ranks above B" — a near-future
  /// feature (multi-source episodes) makes this order semantically meaningful
  /// (top = default playback source). No reorder UI / priority meaning yet.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {anilistId, episode};

  @override
  String get tableName => 'watch_state';
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

@DriftDatabase(
  tables: [
    SeriesCache,
    FileCache,
    LibraryFolders,
    MatchOverrides,
    WatchStates,
    AppSettings,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.e);

  @override
  int get schemaVersion => 6;

  // Migrations are set up deliberately (seam rule: a schema change is a real
  // migration). v2 library_folders; v3 match_overrides; v4 folder sort order;
  // v5 watch_state; v6 app_settings.
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
    },
  );

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

  Future<void> deleteFolder(String path) =>
      (delete(libraryFolders)..where((f) => f.path.equals(path))).go();

  /// Remove a folder and the files under it, then prune orphaned series — all
  /// atomically (so the cache stays consistent immediately, without a rescan).
  Future<void> removeFolderAndFiles(String path) {
    return transaction(() async {
      await (delete(libraryFolders)..where((f) => f.path.equals(path))).go();
      await (delete(
        fileCache,
      )..where((f) => f.path.equals(path) | f.path.like('$path/%'))).go();
      await customStatement(
        'DELETE FROM series_cache WHERE anilist_id NOT IN ('
        'SELECT anilist_id FROM file_cache WHERE anilist_id IS NOT NULL '
        'UNION SELECT anilist_id FROM match_overrides)',
      );
    });
  }

  // --- Match overrides (Stage 5 fix-match). Written ONLY by FixMatchService;
  //     LibrarySync has no reference to these methods (seam #5 by structure). ---

  Future<List<MatchOverrideRow>> allOverrideRows() =>
      select(matchOverrides).get();

  Future<CachedFileRow?> fileByPath(String path) =>
      (select(fileCache)..where((f) => f.path.equals(path))).getSingleOrNull();

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

  // --- App settings (key/value preferences) ---

  Future<String?> getSetting(String key) => (select(
    appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull().then((r) => r?.value);

  Future<void> setSetting(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingRow(key: key, value: value));

  // --- Fill path (used by LibrarySync) ---

  Future<List<CachedFileRow>> allFileRows() => select(fileCache).get();

  /// Apply a computed delta atomically: never half-write a record. Upserts
  /// series + files, deletes removed paths, then prunes series that no longer
  /// have any files.
  Future<void> applySync({
    required List<CachedSeriesRow> seriesUpserts,
    required List<CachedFileRow> fileUpserts,
    required List<String> removedPaths,
  }) {
    return transaction(() async {
      for (final s in seriesUpserts) {
        await into(seriesCache).insertOnConflictUpdate(s);
      }
      for (final f in fileUpserts) {
        await into(fileCache).insertOnConflictUpdate(f);
      }
      if (removedPaths.isNotEmpty) {
        await (delete(fileCache)..where((f) => f.path.isIn(removedPaths))).go();
      }
      await customStatement(
        'DELETE FROM series_cache WHERE anilist_id NOT IN ('
        'SELECT anilist_id FROM file_cache WHERE anilist_id IS NOT NULL '
        'UNION SELECT anilist_id FROM match_overrides)',
      );
    });
  }
}
