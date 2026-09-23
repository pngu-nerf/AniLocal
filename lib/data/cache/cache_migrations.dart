part of 'cache_database.dart';

/// The migration ladder, v1 → v23: every `if (from < n)` step
/// the cache has ever needed, in order, plus the two steps big enough to be
/// methods of their own. A part of `cache_database.dart` (like the generated
/// code) rather than a library: the steps reach the tables and the private
/// id-minting helpers as `this`, and the file stays the one place a schema
/// change is written down — this is the seam CLAUDE.md means by "a deliberate
/// Drift migration, not a reflex".
extension CacheMigrations on CacheDatabase {
  /// `MigrationStrategy.onUpgrade`. Refuses a cache from a newer app before
  /// anything runs, then applies every step inside ONE transaction.
  Future<void> upgradeCache(Migrator m, int from, int to) async {
    // Refused BEFORE the transaction opens, so "before any statement runs"
    // is literally true and the version label on disk is never touched.
    if (from > to) throw CacheNewerThanAppException(from, to);
    await transaction(() async {
      // THE GUARANTEE, made real. Drift does NOT wrap onUpgrade in a
      // transaction (verified against drift 2.33's runner: `_runMigrations`
      // calls `beforeOpen` → `onUpgrade` bare, and the sqlite3 delegate is
      // `NoTransactionDelegate`, so every statement autocommits and the
      // version is stamped last). Without this wrapper a force-quit between
      // two statements left a half-migrated database still stamped with the
      // OLD version; the next launch replayed the same step against the new
      // shape, failed, and drift's sticky `_migrationError` then refused every
      // open for the rest of the process — all user data intact and
      // unreachable, recoverable only by deleting the cache. SQLite DDL is
      // transactional, so this one wrapper makes the whole chain atomic:
      // either every step lands and the version advances, or nothing changed
      // and the next launch retries from a clean state. Drift's own
      // `Migrator.alterTable` opens `database.transaction()` inside a
      // migration, so this is a supported pattern, not a trick.
      if (from < 2) {
        await m.createTable(libraryFolders);
      }
      if (from < 3) {
        await m.createTable(matchOverrides);
      }
      if (from < 4) {
        // `from >= 2`: the v2 step above emits library_folders in its CURRENT
        // shape, sort_order included, so adding it again on a from-<2 path is a
        // duplicate-column error that aborts the whole upgrade. Same hazard the
        // v10 step guards against; it had been missed here and at v9/v12.
        if (from >= 2) {
          await m.addColumn(libraryFolders, libraryFolders.sortOrder);
        }
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
        // Raw SQL, not m.addColumn: id_mal no longer exists in the current
        // table shape (v15 drops it), so there is no generated column to pass.
        // The historical step must still run — v14's seeding reads id_mal, and
        // v15 then drops it — so a pre-v8 cache follows the same path every
        // other cache did.
        await customStatement(
          'ALTER TABLE series_cache ADD COLUMN id_mal INTEGER',
        );
        // Raw SQL for the same reason as id_mal above: skip_segments no
        // longer exists in the current schema (v19 replaces it with
        // skip_source_answers), so there is no generated table to create. The
        // historical step must still run — v19's backfill reads this table.
        await customStatement(
          'CREATE TABLE skip_segments ('
          'anilist_id INTEGER NOT NULL, episode INTEGER NOT NULL, '
          'intro_start_ms INTEGER, intro_end_ms INTEGER, '
          'outro_start_ms INTEGER, outro_end_ms INTEGER, '
          'PRIMARY KEY (anilist_id, episode))',
        );
      }
      if (from < 9) {
        if (from >= 2) {
          // See v4: a from-<2 library_folders already carries these.
          await m.addColumn(libraryFolders, libraryFolders.volumeId);
          await m.addColumn(libraryFolders, libraryFolders.volumeSubpath);
        }
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
        // `from >= 5`: the v5 step emits watch_state in its CURRENT shape,
        // watched_manual included.
        if (from >= 5) {
          await m.addColumn(watchStates, watchStates.watchedManual);
        }
      }
      if (from < 13) {
        // Brand-new per-show preferences table; a from-<13 upgrade just creates
        // it empty, so every existing populated cache is unaffected (no show has
        // an override until the user sets one).
        await m.createTable(showPrefs);
      }
      if (from < 14) {
        await _migrateToSurrogateIdentityV14(m, from);
      }
      if (from < 15) {
        // series_cache.id_mal is now the 'mal' row in series_external_ids, and
        // v14 already seeded it there. Two homes for one fact is exactly the
        // duplication CLAUDE.md forbids, so the column goes; the AniSkip lookup
        // reads the side table instead. Safe to drop: not indexed, not part of
        // any primary key. (v14 seeded it BEFORE this runs, so no data is lost
        // even on a single v13 -> v15 hop.) Unguarded on purpose: the v8 step
        // ADDS id_mal on every path below 8, so the column exists here for
        // every starting version — a `from >= 8` guard left it orphaned on a
        // pre-v8 upgrade, making an upgraded schema differ from a fresh one.
        await m.dropColumn(seriesCache, 'id_mal');
      }
      if (from < 16) {
        // Additive and defaulted, so every existing row keeps its meaning: a
        // pre-v16 skip row came from AniSkip and was never corroborated. Left
        // as '' rather than backfilled to 'aniskip' so "we don't know where
        // this came from" stays distinguishable from "we recorded that it did".
        // The skip_segments steps (v14 rename, v16–v19) are all UNGUARDED: the
        // v8 step creates the table on every path below 8, in its v8 shape, so
        // each of these is valid from any starting version. The `from >= 8`
        // guards they used to carry left a pre-v8 upgrade with an orphaned,
        // never-migrated skip_segments a fresh install does not have.
        await customStatement(
          "ALTER TABLE skip_segments ADD COLUMN source TEXT NOT NULL "
          "DEFAULT ''",
        );
        // Raw SQL: `confidence` no longer exists in the current table shape
        // (v17 replaces it with a verdict per window). The historical step
        // must still run so a v15 cache follows the same path every other
        // cache did, and v17 then drops it.
        await customStatement(
          'ALTER TABLE skip_segments ADD COLUMN confidence '
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 17) {
        // v16's single `confidence` was a placeholder written before the rule
        // existed; D5 needs a verdict per window. Nothing is lost: every v16
        // row was written 0, since nothing ever set it. By the time this runs
        // the column exists on every path — already there for a v16+ cache, or
        // just added by the v16 step above. (An earlier `from >= 16` guard left
        // the orphan behind on exactly the upgrade path a real cache takes.)
        await customStatement(
          'ALTER TABLE skip_segments DROP COLUMN confidence',
        );
        await customStatement(
          'ALTER TABLE skip_segments ADD COLUMN intro_confidence '
          'INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE skip_segments ADD COLUMN outro_confidence '
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (from < 18) {
        // Additive and defaulted to '', which MEANS "produced by unknown
        // inputs" — so every pre-v18 row is re-resolved once on the next
        // refresh and then left alone. Backfilling it to the current key
        // would be the wrong default: it would assert that rows written
        // before the rule existed already satisfy it, and the 140 rows on
        // the reference library that predate even `source` would keep their
        // first-writer-wins state forever.
        await customStatement(
          "ALTER TABLE skip_segments ADD COLUMN resolved_key TEXT NOT NULL "
          "DEFAULT ''",
        );
      }
      if (from < 19) {
        // Stop storing a VERDICT and store the ANSWERS it was derived from.
        // Everything derived moves to the read path, so a rule change no
        // longer needs invalidating — see SkipSourceAnswers.
        await m.createTable(skipSourceAnswers);
        // Backfill, so nothing a user already had disappears. A row whose
        // provenance was never recorded (pre-v16) becomes `legacy`: still
        // usable, but it can never outrank a known source or vote on
        // agreement, because we cannot say who produced it.
        // No `OR IGNORE`: the source key is `(series_id, episode)` and the
        // target adds `source`, so a duplicate is impossible by construction
        // and the clause could only have turned a real constraint failure
        // into silent row loss. A failure here rolls the whole chain back.
        await customStatement(
          'INSERT INTO skip_source_answers '
          '(series_id, episode, source, intro_start_ms, intro_end_ms, '
          'outro_start_ms, outro_end_ms, asked_at_ms) '
          "SELECT series_id, episode, CASE WHEN source = '' THEN '$kLegacySource' "
          'ELSE source END, intro_start_ms, intro_end_ms, outro_start_ms, '
          'outro_end_ms, 0 FROM skip_segments',
        );
        await customStatement('DROP TABLE skip_segments');
      }
      if (from < 20) {
        // v20: the two indexes file_cache lookups always wanted. Pure
        // performance; no row changes.
        await m.createIndex(fileCacheFingerprint);
        await m.createIndex(fileCacheSeries);
      }
      if (from < 21) {
        // v21: Continue watching is "recent first" over a table that grows
        // for the install's lifetime by design (watch_state is never
        // pruned); the sort needs an index. No row changes.
        await m.createIndex(watchStateUpdated);
      }
      if (from < 22) {
        // v22: a source pin names the file, not only its folder. Nullable
        // and additive: every existing row keeps its meaning (folder pin).
        // `from >= 7`: the v7 step emits source_overrides in its CURRENT
        // shape, relative_path included — the same trap every additive
        // column here guards against.
        if (from >= 7) {
          await m.addColumn(sourceOverrides, sourceOverrides.relativePath);
        }
      }
      if (from < 23) {
        // v23: the airing indicator. Five nullable columns on series_cache
        // (status, next air instant + number, finale date, last checked) and
        // a per-show mute on show_preferences. Additive; every existing row
        // reads as "unknown, never checked" until the next scan asks.
        // series_cache is created by onCreate only, so no guard; show_prefs
        // is created by the v13 step in its CURRENT shape, hence `from >= 13`.
        await m.addColumn(seriesCache, seriesCache.airingStatus);
        await m.addColumn(seriesCache, seriesCache.nextAiringAtMs);
        await m.addColumn(seriesCache, seriesCache.nextAiringEpisode);
        await m.addColumn(seriesCache, seriesCache.endDate);
        await m.addColumn(seriesCache, seriesCache.airingCheckedAtMs);
        if (from >= 13) {
          await m.addColumn(showPrefs, showPrefs.airingHidden);
        }
      }
    });
  }

  /// v13 -> v14: `anilist_id` becomes `series_id` everywhere, and external ids
  /// move into their own table.
  ///
  /// The column was never really "AniList's id" in role — it is the app's
  /// universal primary key across eight tables, four of them holding sacred
  /// user data. Renaming it stops the name lying now that a show can come from
  /// a provider other than AniList (or from none of them: 4,655 Kitsu entries
  /// have no AniList id).
  ///
  /// SAFETY: `ALTER TABLE ... RENAME COLUMN` is a SCHEMA-TEXT-ONLY operation —
  /// SQLite rewrites the stored CREATE TABLE (primary-key clause included) and
  /// touches ZERO rows. There is no copy, no INSERT loop, no table rebuild. The
  /// whole onUpgrade runs inside the transaction we open around it (drift does
  /// NOT provide one — see the onUpgrade comment), so the only two
  /// outcomes are "every rename applied" or "rolled back, database byte-for-byte
  /// unchanged". That is a stronger guarantee than the v9 migration shipped
  /// with, which did rebuild a table row by row.
  ///
  /// Identity is PRESERVED: series_id is seeded with the exact value anilist_id
  /// held, so nothing is re-keyed and cover-art files (named by id on disk)
  /// still resolve. No file is touched.
  Future<void> _migrateToSurrogateIdentityV14(Migrator m, int from) async {
    // THE RULE, and it is not obvious: only rename a table that ALREADY EXISTED
    // when this upgrade started. `m.createTable` always emits the table in its
    // CURRENT generated shape, so any table created by an earlier step of this
    // same onUpgrade run was born with `series_id` and has no `anilist_id` to
    // rename — attempting it fails with "no such column". Each entry below is
    // therefore paired with the schema version that CREATES that table.
    //
    // Get this wrong and it only bites users upgrading from an older version,
    // which is exactly the case a single-hop migration test never covers.
    Future<void> renameIfPreExisting(
      int createdAtVersion,
      TableInfo<Table, dynamic> table,
      GeneratedColumn<int> column,
    ) async {
      if (from >= createdAtVersion) {
        await m.renameColumn(table, 'anilist_id', column);
      }
    }

    await renameIfPreExisting(1, seriesCache, seriesCache.seriesId);
    // file_cache exists from v1 but is REBUILT by the v9 step, so from a
    // pre-v9 cache it is already in current shape.
    await renameIfPreExisting(9, fileCache, fileCache.seriesId);
    await renameIfPreExisting(3, matchOverrides, matchOverrides.seriesId);
    await renameIfPreExisting(5, watchStates, watchStates.seriesId);
    await renameIfPreExisting(7, sourceOverrides, sourceOverrides.seriesId);
    // skip_segments is gone from the current schema, so it cannot go through
    // renameIfPreExisting (which needs a generated table) — and it needs NO
    // guard: the v8 step creates it by raw SQL in its v8 shape (anilist_id)
    // on every path below 8, so unlike the generated tables above it never
    // arrives here already renamed.
    await customStatement(
      'ALTER TABLE skip_segments RENAME COLUMN anilist_id TO series_id',
    );
    await renameIfPreExisting(11, hiddenEpisodes, hiddenEpisodes.seriesId);
    await renameIfPreExisting(13, showPrefs, showPrefs.seriesId);

    await m.createTable(seriesExternalIds);

    // Seed the side table from what we already know. Every existing series_id
    // IS an AniList id (that is what it was until this migration), and id_mal
    // is the MAL id AniList gave us.
    //
    // The `> 0` guard is belt-and-braces: placeholder ids are negative and are
    // never persisted to series_cache, but if one ever were, it must not be
    // published as though it were a real AniList id.
    await customStatement(
      "INSERT OR IGNORE INTO series_external_ids (series_id, provider, "
      "external_id) SELECT series_id, 'anilist', CAST(series_id AS TEXT) "
      'FROM series_cache WHERE series_id > 0',
    );
    await customStatement(
      "INSERT OR IGNORE INTO series_external_ids (series_id, provider, "
      "external_id) SELECT series_id, 'mal', CAST(id_mal AS TEXT) "
      'FROM series_cache WHERE id_mal IS NOT NULL',
    );

    // OBLIGATION carried forward: series_cache.id_mal is now duplicated by the
    // 'mal' row above. It stays for now because removing it means repointing
    // the AniSkip lookup, which is a behaviour change and belongs in the
    // provider-abstraction slice, not this identity-only one. Drop it there.
  }

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
    // change; the whole onUpgrade runs in the transaction opened around it.
    await customStatement('ALTER TABLE file_cache RENAME TO _file_cache_v8');
    await m.createTable(fileCache);
    for (final r in oldFiles) {
      final loc = rebaseToFolderRelative(r.read<String>('path'), folderPaths);
      await customStatement(
        'INSERT INTO file_cache (folder_path, relative_path, file_size, '
        'modified_at_ms, series_id, episode_number, parsed_title, '
        'match_score, release_group) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          loc.folderPath,
          loc.relativePath,
          r.read<int>('file_size'),
          r.read<int>('modified_at_ms'),
          // READ side: this row comes from the PRE-v9 table, whose column is
          // still literally `anilist_id`. The INSERT above writes `series_id`
          // because m.createTable(fileCache) built the table in its CURRENT
          // shape. That asymmetry is deliberate — do not "fix" it to match.
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
}
