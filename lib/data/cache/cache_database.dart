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

@DriftDatabase(tables: [SeriesCache, FileCache])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // Migrations are set up from v1 deliberately (seam rule: adding a cached
  // field is a real migration). Future schema changes bump schemaVersion and
  // add steps in onUpgrade.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // No upgrades yet (schemaVersion == 1). Add ordered steps here as the
      // projection grows.
    },
  );

  // --- Read path (used by DriftLibraryRepository) ---

  Future<List<CachedSeriesRow>> allSeriesRows() => select(seriesCache).get();

  Future<List<CachedFileRow>> filesForSeries(int anilistId) =>
      (select(fileCache)..where((f) => f.anilistId.equals(anilistId))).get();

  Future<List<CachedFileRow>> unmatchedFileRows() =>
      (select(fileCache)..where((f) => f.anilistId.isNull())).get();

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
        'DELETE FROM series_cache WHERE anilist_id NOT IN '
        '(SELECT DISTINCT anilist_id FROM file_cache WHERE anilist_id IS NOT NULL)',
      );
    });
  }
}
