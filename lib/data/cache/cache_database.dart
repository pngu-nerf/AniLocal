import 'package:drift/drift.dart';

import '../../domain/models/cache_errors.dart';
import '../../domain/models/external_ids.dart';
import '../../domain/skip_corroboration.dart';
import '../folders/volume_resolver.dart' show rebaseToFolderRelative;
import 'series_identity.dart';

part 'cache_database.g.dart';
part 'cache_migrations.dart';

/// Series metadata projection, keyed by [seriesId]. ONLY fields the UI renders
/// (seam rule: a projection, not a clone). `coverImagePath` is the downloaded
/// local art file so offline browse shows art, not broken images.
@DataClassName('CachedSeriesRow')
class SeriesCache extends Table {
  IntColumn get seriesId => integer()();

  TextColumn get romaji => text().nullable()();
  TextColumn get english => text().nullable()();
  TextColumn get nativeTitle => text().nullable()();
  TextColumn get format => text().nullable()();
  IntColumn get episodeCount => integer().nullable()();
  TextColumn get coverImageUrl => text().nullable()();
  TextColumn get coverImagePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {seriesId};

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
/// "unchanged" key for incremental rescans. A null [seriesId] is a
/// known-unmatched file — it persists across rescans (Stage 5 fixes it).
/// Indexed for the two ways rows are looked up other than by key: fix-match
/// finds a file by its content fingerprint, and the prune asks "which series
/// still have files". Neither had an index; both were full scans.
@TableIndex(name: 'file_cache_fingerprint', columns: {#fileSize, #modifiedAtMs})
@TableIndex(name: 'file_cache_series', columns: {#seriesId})
@DataClassName('CachedFileRow')
class FileCache extends Table {
  TextColumn get folderPath => text()();
  TextColumn get relativePath => text()();
  IntColumn get fileSize => integer()();
  IntColumn get modifiedAtMs => integer()();
  IntColumn get seriesId => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();
  TextColumn get parsedTitle => text()();
  RealColumn get matchScore => real().withDefault(const Constant(0))();
  TextColumn get releaseGroup => text().nullable()();

  /// Identification lifecycle, meaningful ONLY while [seriesId] is null. This
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
  /// rows are unaffected (the flag is ignored when [seriesId] is set).
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
  /// in the folders screen (see `reorderFolders` on the repository); stable across relaunch.
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
/// [anchoredEpisode] is the episode position WITHIN [seriesId] (file "12" of a
/// continuously-numbered show = Season-2-entry episode 1). The displayed number
/// is derived: `displayContinuous ? anchoredEpisode + continuousOffset
/// : anchoredEpisode`, where [continuousOffset] is the real prior-season episode
/// count captured at assign time (never hardcoded).
@DataClassName('MatchOverrideRow')
class MatchOverrides extends Table {
  IntColumn get fileSize => integer()();
  IntColumn get modifiedAtMs => integer()();
  IntColumn get seriesId => integer()();
  IntColumn get anchoredEpisode => integer().nullable()();
  IntColumn get continuousOffset => integer().withDefault(const Constant(0))();
  BoolColumn get displayContinuous =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {fileSize, modifiedAtMs};

  @override
  String get tableName => 'match_overrides';
}

/// Local watch state (Stage 6). Keyed by EPISODE IDENTITY — [seriesId] + the
/// anchored (AniList-faithful) [episode] position — NOT by file path or player
/// session. This is what survives a file move and what the future multi-source
/// stage needs: "resume episode 5" is episode 5 whatever file played it.
@TableIndex(name: 'watch_state_updated', columns: {#updatedAtMs})
@DataClassName('WatchStateRow')
class WatchStates extends Table {
  IntColumn get seriesId => integer()();
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
  Set<Column> get primaryKey => {seriesId, episode};

  @override
  String get tableName => 'watch_state';
}

/// Manual SOURCE override (multi-source episodes). One logical episode = the
/// files sharing an episode identity `(seriesId, anchored episode)` across
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
  IntColumn get seriesId => integer()();
  IntColumn get episode => integer()();
  TextColumn get folderPath => text()();

  /// v22: WHICH file in [folderPath] — two copies of one episode in the same
  /// folder (a 0-byte download beside the good one) used to be one pin that
  /// always played the alphabetically-first. Null = a legacy folder pin,
  /// resolved as before (the folder's first copy).
  TextColumn get relativePath => text().nullable()();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {seriesId, episode};

  @override
  String get tableName => 'source_overrides';
}

/// WHAT EACH SKIP SOURCE SAID about one episode — the raw answers, not a
/// verdict. One row per (episode, source); a row EXISTS iff that source has
/// been asked, and NULL windows mean "asked, and it had nothing", which is the
/// distinction the chain has always cared about ("no data" is not "failed").
///
/// **Nothing derived is stored here, deliberately.** Which window you get, how
/// far to trust it, and the minimum-length floor are all computed on the READ
/// path from these answers (`resolveEpisodeSkips`). That is the same choice the
/// minimum-skip floor already made, for the same reason: a stored verdict is a
/// cache of a rule's output, so every change to the rule becomes a cache
/// invalidation problem. Before v19 that was handled by a hand-bumped
/// generation counter whose failure was SILENT — forget it and the new rule
/// reaches only newly scanned episodes. Now there is nothing to invalidate:
/// reordering sources, switching one off or on, toggling cross-checking, and
/// changing the agreement rule itself all take effect immediately, everywhere,
/// with no refresh at all.
///
/// A source is asked only when it has no row for that episode, so answers
/// accumulate once and are never re-fetched. A FAILURE writes nothing, which is
/// what leaves it to be retried.
@DataClassName('SkipSourceAnswerRow')
class SkipSourceAnswers extends Table {
  IntColumn get seriesId => integer()();
  IntColumn get episode => integer()();

  /// The source's token (`aniskip`, `chapters`, …), or `legacy` for a window
  /// migrated from v18 whose provenance was never recorded. A legacy answer is
  /// used only when no known source has anything, and never votes on
  /// agreement — unknown provenance must not corroborate.
  TextColumn get source => text()();

  /// Null when this source has nothing for this window. Times are ms from the
  /// start of the file.
  IntColumn get introStartMs => integer().nullable()();
  IntColumn get introEndMs => integer().nullable()();
  IntColumn get outroStartMs => integer().nullable()();
  IntColumn get outroEndMs => integer().nullable()();

  /// When we asked. Not read today; it is what a future "re-ask answers older
  /// than N" policy would need, and it costs one integer.
  IntColumn get askedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {seriesId, episode, source};

  @override
  String get tableName => 'skip_source_answers';
}

/// User-hidden MISSING episodes (the missing-episodes feature). Keyed by EPISODE
/// IDENTITY ([seriesId] + the anchored [episode] position), consistent with
/// watch_state / source_overrides / skip_source_answers. A hidden episode is removed
/// from the show's episode list (no ghost tile) and excluded from completeness
/// counts. Hiding is always per-episode, even when the action targets a bundle.
///
/// SACRED (seam #5): the auto fill path (LibrarySync → applySync) and
/// refreshMetadata have NO write path to this table, so a rescan / metadata
/// refresh never wipes hidden state — it is persisted user data, like a
/// fix-match or a source pin. The only writers are the hide/unhide UI actions.
@DataClassName('HiddenEpisodeRow')
class HiddenEpisodes extends Table {
  IntColumn get seriesId => integer()();
  IntColumn get episode => integer()();
  IntColumn get hiddenAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {seriesId, episode};

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

/// PER-SHOW preferences, keyed by show identity ([seriesId]). Sacred user data:
/// written ONLY by the per-show menu actions; the fill path (applySync) and
/// refreshMetadata never touch it, so a rescan/refresh can't wipe it (seam #5) —
/// like watch_state / source_overrides / hidden_episodes. Extensible: a new
/// per-show pref is a new column here + a field on the domain ShowPreferences,
/// NOT a parallel store. Absent row = all defaults.
@DataClassName('ShowPreferenceRow')
class ShowPrefs extends Table {
  IntColumn get seriesId => integer()();

  /// Cover display mode token (see PictureMode): 'normal' / 'blur' / 'removed'.
  TextColumn get pictureMode => text().withDefault(const Constant('normal'))();

  /// Whether the card's "Next episode" button is hidden for this show.
  BoolColumn get nextEpisodeHidden =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {seriesId};

  @override
  String get tableName => 'show_preferences';
}

/// A show's ids on OTHER databases, keyed by our own [SeriesCache.seriesId].
///
/// Exists because `series_id` is now an OPAQUE LOCAL SURROGATE, not any
/// provider's id — sources are user-reorderable, and 4,655 anime on Kitsu have
/// no AniList id at all, so no single provider's id could serve as the key
/// without stranding user data. External ids are ATTRIBUTES of a show here,
/// never its identity.
///
/// [externalId] is TEXT so a future provider with a non-numeric id needs no
/// migration. The UNIQUE (provider, external_id) index is load-bearing: it
/// turns "the same show got minted twice under two ids" from a silent fork
/// that strands watch progress into a loud constraint failure.
///
/// Rows here are NEVER pruned (see `_pruneOrphans`): this table is the
/// identity memory that lets a show whose files left and came back resolve to
/// the same `series_id` and reattach its watch state. It is bounded by the
/// number of distinct shows ever seen, not by the current library.
class SeriesExternalIds extends Table {
  IntColumn get seriesId => integer()();

  /// Which database the id belongs to: 'anilist', 'mal', 'kitsu', 'anidb'.
  TextColumn get provider => text()();

  TextColumn get externalId => text()();

  @override
  Set<Column> get primaryKey => {seriesId, provider};

  /// Load-bearing: two series claiming the same provider id is the shape that
  /// silently forks a show and strands watch progress under an orphaned id.
  /// This turns it into a loud constraint failure instead.
  @override
  List<Set<Column>> get uniqueKeys => [
    {provider, externalId},
  ];

  @override
  String get tableName => 'series_external_ids';
}

@DriftDatabase(
  tables: [
    SeriesCache,
    FileCache,
    LibraryFolders,
    MatchOverrides,
    WatchStates,
    SourceOverrides,
    SkipSourceAnswers,
    HiddenEpisodes,
    AppSettings,
    ShowPrefs,
    SeriesExternalIds,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.e);

  /// The schema this build writes, readable without an instance (the startup
  /// log line and the diagnostics report want it before the database opens).
  static const int currentSchemaVersion = 22;

  @override
  int get schemaVersion => currentSchemaVersion;

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
  // a brand-new table so existing populated caches are untouched; v14 surrogate
  // series identity; v15 series_cache.id_mal dropped; v16 skip_segments.source;
  // v17 per-window skip confidence; v18 skip_segments.resolved_key — the
  // resolution inputs a skip row came from (superseded a commit later); v19
  // skip_source_answers replaces skip_segments entirely (raw per-source
  // answers, verdicts derived on read); v20 two indexes on file_cache; v21
  // watch_state(updated_at_ms) index; v22 source_overrides.relative_path —
  // a pin names the FILE, not only its folder (additive, nullable: a null is
  // the legacy folder pin and resolves exactly as before).
  //
  // v8 RECLAIMED: it was briefly scratch on an unshipped branch (series_relations,
  // the "Up Next" overshoot) then reverted — it never reached main and no DB sits
  // at 8 (drift normalized the one dev cache that touched it back to 7), so the
  // number was free. This v8 adds idMal + skip_segments, NOT series_relations, so
  // there's no clash even with a backup-restored cache carrying the orphan table.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // WAL: the standard single-writer desktop setting — a scan's multi-hundred
    // statement transaction stops fsyncing a rollback journal, and readers no
    // longer block on a writer. busy_timeout: a second instance of the app (or
    // a stray tool holding the file) waits up to five seconds for the lock
    // rather than failing at once; a scan's transaction can hold it longer
    // than that, in which case the failure is merely later, and it surfaces
    // as the library screen's error panel rather than a spinner. Both run
    // OUTSIDE the migration transaction below — journal_mode cannot be changed
    // inside one — because drift calls beforeOpen after onUpgrade completes.
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
    onUpgrade: upgradeCache,
  );

  // --- Read path (used by DriftLibraryRepository) ---

  Future<List<CachedSeriesRow>> allSeriesRows() => select(seriesCache).get();

  // --- Library folders (Stage 5) ---

  Future<List<LibraryFolderRow>> allFolderRows() => (select(
    libraryFolders,
  )..orderBy([(f) => OrderingTerm(expression: f.sortOrder)])).get();

  /// Append a folder to the end of the priority order (highest sortOrder + 1).
  Future<void> insertFolder(String path) => transaction(() async {
    // MAX in SQL, inside the transaction, so two adds cannot both read the
    // same "next" order; the old read-modify-write materialised every row.
    final next = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM library_folders',
    ).getSingle();
    await into(libraryFolders).insertOnConflictUpdate(
      LibraryFolderRow(
        path: path,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
        sortOrder: next.read<int>('next'),
      ),
    );
  });

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

  /// Remove a folder and the files under it, then prune orphaned series — all
  /// atomically (so the cache stays consistent immediately, without a rescan).
  /// Files are keyed by their owning folder, so removal is an exact match on
  /// `folderPath` (no path-prefix scan).
  Future<void> removeFolderAndFiles(String path) {
    return transaction(() async {
      await (delete(libraryFolders)..where((f) => f.path.equals(path))).go();
      await (delete(fileCache)..where((f) => f.folderPath.equals(path))).go();
      await _pruneOrphans(includeOverrides: false);
    });
  }

  // --- Per-series reads. Each hits an index (file_cache_series, or a PK that
  //     leads with series_id), so answering for ONE show costs one show, not
  //     the library. The read path uses these for the show page, the player's
  //     rail and every auto-advance. ---

  Future<List<CachedFileRow>> fileRowsForSeries(int seriesId) =>
      (select(fileCache)..where((f) => f.seriesId.equals(seriesId))).get();

  Future<List<MatchOverrideRow>> overrideRowsForSeries(int seriesId) =>
      (select(matchOverrides)..where((o) => o.seriesId.equals(seriesId))).get();

  Future<List<SourceOverrideRow>> sourceOverrideRowsForSeries(int seriesId) =>
      (select(
        sourceOverrides,
      )..where((o) => o.seriesId.equals(seriesId))).get();

  Future<List<WatchStateRow>> watchStateRowsForSeries(int seriesId) =>
      (select(watchStates)..where((w) => w.seriesId.equals(seriesId))).get();

  Future<List<SkipSourceAnswerRow>> skipAnswersForSeries(int seriesId) =>
      (select(
        skipSourceAnswers,
      )..where((s) => s.seriesId.equals(seriesId))).get();

  /// CONFIRMED-unmatched files: no series, not pending, and no fix-match
  /// override for the fingerprint (an override makes a file matched whatever
  /// its auto row says). One COUNT, no rows materialised.
  Future<int> unmatchedFileCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM file_cache f '
      'WHERE f.series_id IS NULL AND f.pending_identification = 0 '
      'AND NOT EXISTS (SELECT 1 FROM match_overrides o '
      'WHERE o.file_size = f.file_size AND o.modified_at_ms = f.modified_at_ms)',
      readsFrom: {fileCache, matchOverrides},
    ).getSingle();
    return row.read<int>('n');
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
  /// One transaction: a seeded series row and its AniList id row are one
  /// fact, and `applySync` already wrote them together — this path did not.
  Future<void> upsertSeries(CachedSeriesRow row) => transaction(() async {
    await into(seriesCache).insertOnConflictUpdate(row);
    await _recordProviderIds(row);
  });

  Future<CachedSeriesRow?> seriesRow(int seriesId) => (select(
    seriesCache,
  )..where((r) => r.seriesId.equals(seriesId))).getSingleOrNull();

  /// Record the one provider id the id band itself implies.
  ///
  /// An id in the PROVIDER-SEEDED band IS an AniList id by definition (see
  /// `series_identity.dart`), so caching such a series is enough to know that
  /// mapping. Every OTHER id a provider reports — MAL, Kitsu — is learned via
  /// [ensureSeriesId], which is the single place that reasons about identity.
  Future<void> _recordProviderIds(CachedSeriesRow row) async {
    // Placeholders are negative and never reach series_cache; a minted id has
    // no AniList id at all. Guard both.
    if (!isProviderSeededSeriesId(row.seriesId)) return;
    await into(seriesExternalIds).insertOnConflictUpdate(
      SeriesExternalId(
        seriesId: row.seriesId,
        provider: kAnilistProvider,
        externalId: '${row.seriesId}',
      ),
    );
  }

  /// Resolve [ids] to a local series identity, minting one only if no existing
  /// series already carries ANY of them.
  ///
  /// THE SOLE MINTING SITE, and the rule matters more than it looks:
  ///
  /// > A show first identified through Kitsu mints id `M`, and six episodes get
  /// > watched — `watch_state` rows under `M`. Later AniList is healthy and
  /// > returns the same show. If we looked it up only by the ANSWERING
  /// > provider's id we would find nothing, mint `M'`, and the show would fork
  /// > in two — six episodes of progress stranded under an id nothing
  /// > references any more.
  ///
  /// So the lookup matches on EVERY id the caller reports, not just the one the
  /// provider is authoritative for. Both AniList and Kitsu publish MAL ids, so
  /// `mal` is the practical bridge between them.
  ///
  /// When SEVERAL existing series match — two rows that turn out to be the same
  /// show — this deliberately does NOT merge them. Merging would move sacred
  /// rows on the fill path, which seam #5 forbids, and a silently clobbered
  /// fix-match is unrecoverable. The lowest matching id wins for the new
  /// mapping; the other row is left exactly as it is.
  ///
  /// Runs in ONE transaction so a crash between allocating the counter and
  /// writing the row cannot leak or reuse an id.
  Future<int> ensureSeriesId(ExternalIds ids) async {
    if (ids.isEmpty) {
      throw ArgumentError('ensureSeriesId needs at least one external id');
    }
    return transaction(() async {
      final matches = <int>{};
      for (final entry in ids.byProvider.entries) {
        final rows =
            await (select(seriesExternalIds)..where(
                  (e) =>
                      e.provider.equals(entry.key) &
                      e.externalId.equals('${entry.value}'),
                ))
                .get();
        matches.addAll(rows.map((r) => r.seriesId));
      }

      // Lowest wins — an arbitrary but STABLE choice, so repeated calls with
      // the same inputs keep resolving to the same identity.
      //
      // With no match, an AniList id becomes the series_id directly rather than
      // minting. That IS the provider-seeded band (see series_identity.dart):
      // every id in it is an AniList id, which is what the v14 migration seeded
      // and what keeps cover-art filenames stable. Minting is reserved for the
      // case that band cannot express — a show AniList does not have.
      final seriesId = matches.isNotEmpty
          ? matches.reduce((a, b) => a < b ? a : b)
          : (ids.anilist ?? await _mintSeriesId());

      // Record anything newly learned — but never STEAL an id that already
      // belongs to a different series. That happens when one answer claims ids
      // we had recorded against two separate identities: they are really one
      // show. Re-pointing the mapping here would be a merge in all but name,
      // and merging on the fill path can clobber a fix-match unrecoverably
      // (seam #5). So the conflicting mapping is left exactly where it is; the
      // UNIQUE (provider, external_id) index is what makes that detectable
      // rather than silent.
      for (final entry in ids.byProvider.entries) {
        final existing =
            await (select(seriesExternalIds)..where(
                  (e) =>
                      e.provider.equals(entry.key) &
                      e.externalId.equals('${entry.value}'),
                ))
                .getSingleOrNull();
        if (existing != null && existing.seriesId != seriesId) continue;
        await into(seriesExternalIds).insertOnConflictUpdate(
          SeriesExternalId(
            seriesId: seriesId,
            provider: entry.key,
            externalId: '${entry.value}',
          ),
        );
      }
      return seriesId;
    });
  }

  /// Next surrogate id for a show no provider-seeded id covers. Monotonic and
  /// stored in app_settings, so it needs no schema of its own.
  Future<int> _mintSeriesId() async {
    final row = await (select(
      appSettings,
    )..where((s) => s.key.equals(_nextMintedIdKey))).getSingleOrNull();
    // The counter lives in the same hand-editable settings table as the
    // user's preferences. If it is missing or corrupt, restarting at the base
    // would RE-ISSUE ids already assigned — a silent merge of two shows, the
    // exact failure this whole method exists to prevent. So the floor is
    // whatever minted id is already in use, from the identity table (which is
    // never pruned) and the series cache.
    final counter = int.tryParse(row?.value ?? '');
    final int next;
    if (counter != null) {
      next = counter;
    } else {
      final used = await customSelect(
        'SELECT MAX(id) AS m FROM ('
        'SELECT MAX(series_id) AS id FROM series_external_ids WHERE series_id >= ? '
        'UNION ALL SELECT MAX(series_id) FROM series_cache WHERE series_id >= ?)',
        variables: [
          Variable.withInt(kMintedSeriesIdBase),
          Variable.withInt(kMintedSeriesIdBase),
        ],
      ).getSingle();
      final max = used.readNullable<int>('m');
      next = max == null ? kMintedSeriesIdBase : max + 1;
    }
    await into(appSettings).insertOnConflictUpdate(
      AppSettingRow(key: _nextMintedIdKey, value: '${next + 1}'),
    );
    return next;
  }

  static const String _nextMintedIdKey = 'next_minted_series_id';

  /// series_id -> everything other databases call it, for the read path.
  /// A minted series simply has fewer entries (no 'anilist' row at all).
  Future<Map<int, ExternalIds>> externalIdsBySeriesId() async =>
      _externalIdsOf(await select(seriesExternalIds).get());

  /// The provider ids of ONE series — the per-show read, indexed by the PK.
  Future<ExternalIds> externalIdsFor(int seriesId) async {
    final rows = await (select(
      seriesExternalIds,
    )..where((r) => r.seriesId.equals(seriesId))).get();
    return _externalIdsOf(rows)[seriesId] ?? ExternalIds.empty;
  }

  Map<int, ExternalIds> _externalIdsOf(List<SeriesExternalId> rows) {
    final byProvider = <int, Map<String, int>>{};
    for (final r in rows) {
      final value = int.tryParse(r.externalId);
      if (value == null) continue; // a non-numeric provider id we don't model
      (byProvider[r.seriesId] ??= {})[r.provider] = value;
    }
    return {
      for (final e in byProvider.entries) e.key: ExternalIds.fromMap(e.value),
    };
  }

  Future<void> upsertOverride(MatchOverrideRow row) =>
      into(matchOverrides).insertOnConflictUpdate(row);

  /// A fix-match's series row and its override in ONE transaction. Written
  /// as two, a scan batch's prune landing between them deleted the series
  /// referenced by neither table — the hazard `upsertSeries`'s doc named.
  Future<void> upsertSeriesWithOverrides(
    CachedSeriesRow series,
    List<MatchOverrideRow> overrides,
  ) => transaction(() async {
    await upsertSeries(series);
    for (final o in overrides) {
      await into(matchOverrides).insertOnConflictUpdate(o);
    }
  });

  /// Move fix-match overrides from an old fingerprint to a new one: the file
  /// at the same path changed bytes (a `touch`, a re-download, an in-place
  /// tag edit, a backup restore). Overrides are keyed by fingerprint, so
  /// without this the user's correction matched no file and the next prune
  /// deleted it. `OR IGNORE`: if the new fingerprint already carries an
  /// override, that one stands.
  Future<void> rekeyOverrides(
    List<(({int size, int modifiedMs}), ({int size, int modifiedMs}))> pairs,
  ) => transaction(() async {
    for (final (from, to) in pairs) {
      await customStatement(
        'UPDATE OR IGNORE match_overrides SET file_size = ?, modified_at_ms = ? '
        'WHERE file_size = ? AND modified_at_ms = ?',
        [to.size, to.modifiedMs, from.size, from.modifiedMs],
      );
    }
  });

  /// The series a file is identified under RIGHT NOW, by its owning folder
  /// and current path — null when it is still pending or unknown. For a
  /// write that arrives carrying a placeholder id after the scan has
  /// identified the file: the row must go under the real id or it is
  /// stranded on a dead placeholder.
  Future<int?> seriesIdForFile(String folderPath, String fileRef) async {
    final row = await customSelect(
      'SELECT series_id FROM file_cache WHERE folder_path = ? '
      "AND series_id IS NOT NULL AND substr(?, -length(relative_path)) = relative_path "
      'LIMIT 1',
      variables: [Variable<String>(folderPath), Variable<String>(fileRef)],
      readsFrom: {fileCache},
    ).getSingleOrNull();
    return row?.read<int?>('series_id');
  }

  Future<void> deleteOverride(int fileSize, int modifiedAtMs) =>
      (delete(matchOverrides)..where(
            (o) =>
                o.fileSize.equals(fileSize) &
                o.modifiedAtMs.equals(modifiedAtMs),
          ))
          .go();

  // --- Watch state (Stage 6). Keyed by episode identity (seriesId, episode). ---

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

  /// Progress-only write. INSERT … ON CONFLICT DO UPDATE in ONE statement, so
  /// the player's once-a-second save cannot interleave with a "mark watched"
  /// and lose one of them — the old read-then-upsert pair could. The watched
  /// and manual flags are preserved by never being in the SET list.
  Future<void> saveProgressRow({
    required int seriesId,
    required int episode,
    required int resumePositionMs,
    required int durationMs,
    required int updatedAtMs,
  }) => customStatement(
    'INSERT INTO watch_state (series_id, episode, resume_position_ms, '
    'duration_ms, watched, watched_manual, updated_at_ms) '
    'VALUES (?, ?, ?, ?, 0, 0, ?) '
    'ON CONFLICT(series_id, episode) DO UPDATE SET '
    'resume_position_ms = excluded.resume_position_ms, '
    'duration_ms = excluded.duration_ms, '
    'updated_at_ms = excluded.updated_at_ms',
    [seriesId, episode, resumePositionMs, durationMs, updatedAtMs],
  );

  /// The AUTO/threshold watched write: a no-op on a row the user set by hand
  /// (the WHERE), marking watched clears resume so the episode leaves
  /// "Continue watching", and an existing duration is kept.
  /// Returns the rows written: 1 when the mark applied, 0 when a manual
  /// override held the row.
  Future<int> setWatchedAutoRow({
    required int seriesId,
    required int episode,
    required bool watched,
    required int durationMs,
    required int updatedAtMs,
  }) => customUpdate(
    'INSERT INTO watch_state (series_id, episode, resume_position_ms, '
    'duration_ms, watched, watched_manual, updated_at_ms) '
    'VALUES (?, ?, 0, ?, ?, 0, ?) '
    'ON CONFLICT(series_id, episode) DO UPDATE SET '
    'watched = excluded.watched, '
    'resume_position_ms = CASE WHEN excluded.watched THEN 0 '
    'ELSE watch_state.resume_position_ms END, '
    'updated_at_ms = excluded.updated_at_ms '
    'WHERE watch_state.watched_manual = 0',
    variables: [
      Variable<int>(seriesId),
      Variable<int>(episode),
      Variable<int>(durationMs),
      Variable<int>(watched ? 1 : 0),
      Variable<int>(updatedAtMs),
    ],
    updates: {watchStates},
    updateKind: UpdateKind.insert,
  );

  /// The sticky MANUAL write: sets watched and marks it manual; resume and
  /// duration are untouched.
  Future<void> setWatchedManualRow({
    required int seriesId,
    required int episode,
    required bool watched,
    required int durationMs,
    required int updatedAtMs,
  }) => customStatement(
    'INSERT INTO watch_state (series_id, episode, resume_position_ms, '
    'duration_ms, watched, watched_manual, updated_at_ms) '
    'VALUES (?, ?, 0, ?, ?, 1, ?) '
    'ON CONFLICT(series_id, episode) DO UPDATE SET '
    'watched = excluded.watched, watched_manual = 1, '
    'updated_at_ms = excluded.updated_at_ms',
    [seriesId, episode, durationMs, watched ? 1 : 0, updatedAtMs],
  );

  Future<WatchStateRow?> watchStateFor(int seriesId, int episode) =>
      (select(watchStates)..where(
            (w) => w.seriesId.equals(seriesId) & w.episode.equals(episode),
          ))
          .getSingleOrNull();

  Future<void> upsertWatchState(WatchStateRow row) =>
      into(watchStates).insertOnConflictUpdate(row);

  /// Remove an episode's watch state entirely (dismiss from "Continue
  /// watching" without marking it watched).
  Future<void> deleteWatchState(int seriesId, int episode) =>
      (delete(watchStates)..where(
            (w) => w.seriesId.equals(seriesId) & w.episode.equals(episode),
          ))
          .go();

  // --- Source overrides (multi-source). Written ONLY by the source-selection
  //     path; LibrarySync's fill path (applySync) never touches this table, so
  //     a rescan cannot clobber a manual source choice (seam #5). ---

  Future<List<SourceOverrideRow>> allSourceOverrideRows() =>
      select(sourceOverrides).get();

  Future<void> upsertSourceOverride(SourceOverrideRow row) =>
      into(sourceOverrides).insertOnConflictUpdate(row);

  Future<void> deleteSourceOverride(int seriesId, int episode) =>
      (delete(sourceOverrides)..where(
            (s) => s.seriesId.equals(seriesId) & s.episode.equals(episode),
          ))
          .go();

  // --- Skip answers (auto-skip). One row per (episode, source) — what each
  //     source SAID, filled at scan/refresh time; read
  //     offline during playback. ---

  Future<List<SkipSourceAnswerRow>> allSkipAnswers() =>
      select(skipSourceAnswers).get();

  Future<List<SkipSourceAnswerRow>> skipAnswersFor(int seriesId, int episode) =>
      (select(skipSourceAnswers)..where(
            (s) => s.seriesId.equals(seriesId) & s.episode.equals(episode),
          ))
          .get();

  /// Record what ONE source said (the refresh backfill — no pruning, so
  /// fix-matches and watch state are untouched).
  Future<void> upsertSkipAnswer(SkipSourceAnswerRow row) =>
      into(skipSourceAnswers).insertOnConflictUpdate(row);

  /// One transaction for a batch of answers (a refresh writes them per
  /// episode; hundreds of autocommits was hundreds of fsyncs).
  Future<void> upsertSkipAnswers(List<SkipSourceAnswerRow> rows) {
    if (rows.isEmpty) return Future.value();
    return transaction(() async {
      for (final r in rows) {
        await into(skipSourceAnswers).insertOnConflictUpdate(r);
      }
    });
  }

  // --- Hidden episodes (missing-episodes feature). Written ONLY by the
  //     hide/unhide UI actions; the fill path (applySync) and refreshMetadata
  //     never touch this table, so a rescan/refresh can't wipe it (seam #5). ---

  Future<List<HiddenEpisodeRow>> allHiddenRows() =>
      select(hiddenEpisodes).get();

  Future<List<HiddenEpisodeRow>> hiddenRowsFor(int seriesId) =>
      (select(hiddenEpisodes)..where((h) => h.seriesId.equals(seriesId))).get();

  /// Hide a set of episode positions for one series (per-episode, even when the
  /// hide action targeted a bundle). Idempotent upserts in one transaction.
  Future<void> hideEpisodes(int seriesId, List<int> episodes) =>
      transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final ep in episodes) {
          await into(hiddenEpisodes).insertOnConflictUpdate(
            HiddenEpisodeRow(seriesId: seriesId, episode: ep, hiddenAtMs: now),
          );
        }
      });

  /// Unhide a set of episode positions for one series.
  Future<void> unhideEpisodes(int seriesId, List<int> episodes) =>
      transaction(() async {
        for (final ep in episodes) {
          await (delete(hiddenEpisodes)..where(
                (h) => h.seriesId.equals(seriesId) & h.episode.equals(ep),
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

  Future<ShowPreferenceRow?> showPrefFor(int seriesId) => (select(
    showPrefs,
  )..where((p) => p.seriesId.equals(seriesId))).getSingleOrNull();

  /// One field of a show's preferences, leaving the other as it is — a single
  /// statement, so two menu actions racing cannot lose each other's field.
  Future<void> setShowPictureMode(
    int seriesId,
    String pictureMode,
  ) => customStatement(
    'INSERT INTO show_preferences (series_id, picture_mode, '
    'next_episode_hidden) VALUES (?, ?, 0) '
    'ON CONFLICT(series_id) DO UPDATE SET picture_mode = excluded.picture_mode',
    [seriesId, pictureMode],
  );

  Future<void> setShowNextEpisodeHidden(int seriesId, {required bool hidden}) =>
      customStatement(
        "INSERT INTO show_preferences (series_id, picture_mode, "
        "next_episode_hidden) VALUES (?, 'normal', ?) "
        'ON CONFLICT(series_id) DO UPDATE SET '
        'next_episode_hidden = excluded.next_episode_hidden',
        [seriesId, hidden ? 1 : 0],
      );

  /// The global "Hide Next Episode" switch: every cached show's flag, ONE
  /// statement (was one upsert per show, un-transactioned), each show's
  /// picture mode preserved.
  Future<void> setAllNextEpisodeHidden({required bool hidden}) =>
      customStatement(
        'INSERT INTO show_preferences (series_id, picture_mode, '
        'next_episode_hidden) '
        // `WHERE true` disambiguates INSERT…SELECT from the upsert clause —
        // SQLite's documented parsing quirk, not a filter.
        "SELECT series_id, 'normal', ? FROM series_cache WHERE true "
        'ON CONFLICT(series_id) DO UPDATE SET '
        'next_episode_hidden = excluded.next_episode_hidden',
        [hidden ? 1 : 0],
      );

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
  ///
  /// [prune] runs [pruneOrphans] inside the same transaction. The scan passes
  /// `false` for its per-batch commits and prunes ONCE at the end of the run:
  /// the three full-table sweeps used to run 24 times per 600-title scan, each
  /// inside a write transaction every UI read had to wait behind.
  Future<void> applySync({
    required List<CachedSeriesRow> seriesUpserts,
    required List<CachedFileRow> fileUpserts,
    required List<(String folderPath, String relativePath)> removedKeys,
    List<SkipSourceAnswerRow> skipUpserts = const [],
    List<(int placeholderId, int realId)> promotions = const [],
    bool prune = true,
  }) {
    return transaction(() async {
      for (final s in seriesUpserts) {
        await into(seriesCache).insertOnConflictUpdate(s);
        await _recordProviderIds(s);
      }
      for (final f in fileUpserts) {
        await into(fileCache).insertOnConflictUpdate(f);
      }
      for (final s in skipUpserts) {
        await into(skipSourceAnswers).insertOnConflictUpdate(s);
      }
      for (final (placeholderId, realId) in promotions) {
        await customStatement(
          'UPDATE OR IGNORE watch_state SET series_id = ? '
          'WHERE series_id = ? AND episode >= 0',
          [realId, placeholderId],
        );
        await customStatement('DELETE FROM watch_state WHERE series_id = ?', [
          placeholderId,
        ]);
      }
      for (final k in removedKeys) {
        await (delete(fileCache)..where(
              (f) => f.folderPath.equals(k.$1) & f.relativePath.equals(k.$2),
            ))
            .go();
      }
      if (prune) await _pruneOrphans(includeOverrides: true);
    });
  }

  /// The scan's end-of-run prune — the same policy [applySync] applies when
  /// asked to, in its own transaction. See [_pruneOrphans] for what goes.
  Future<void> pruneOrphans() =>
      transaction(() => _pruneOrphans(includeOverrides: true));

  /// Everything DERIVED from the files goes when the files go — one policy,
  /// called from both paths that remove files (`applySync`, a folder removal)
  /// so they cannot drift.
  ///
  /// Pruned: a series no file and no override references; its stored skip
  /// answers (re-asked if it returns); and, from a scan only, a fix-match
  /// override whose fingerprint matches no cached file — it is unreachable
  /// once the file is gone from every library folder, and left behind it
  /// pinned a phantom series forever. NOT pruned, on purpose:
  /// `series_external_ids`, `watch_state`, `hidden_episodes` and
  /// `show_preferences`. Those are the show's MEMORY, keyed by our surrogate
  /// id; keeping the id map is what lets a show that leaves and comes back
  /// resolve to the SAME id and reattach its watch progress — a Kitsu-only
  /// show would otherwise be minted afresh and lose it.
  ///
  /// Overrides are kept when a folder is removed rather than scanned: removing
  /// and re-adding a folder is a normal repair step, and the fingerprint-keyed
  /// override is exactly what lets the re-added files keep their fix-match.
  Future<void> _pruneOrphans({required bool includeOverrides}) async {
    if (includeOverrides) {
      await customStatement(
        'DELETE FROM match_overrides WHERE NOT EXISTS ('
        'SELECT 1 FROM file_cache f WHERE f.file_size = match_overrides.file_size '
        'AND f.modified_at_ms = match_overrides.modified_at_ms)',
      );
    }
    await customStatement(
      'DELETE FROM series_cache WHERE series_id NOT IN ('
      'SELECT series_id FROM file_cache WHERE series_id IS NOT NULL '
      'UNION SELECT series_id FROM match_overrides)',
    );
    await customStatement(
      'DELETE FROM skip_source_answers WHERE series_id NOT IN ('
      'SELECT series_id FROM series_cache)',
    );
  }
}
