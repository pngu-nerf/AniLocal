import 'dart:io';

import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anilocal/domain/models/cache_errors.dart';

/// The complete v13 schema — every table still keyed by `anilist_id`, plus
/// show_preferences. Copied forward from `migration_v13_test.dart`'s `_v12Ddl`
/// with the show_preferences table appended, deliberately rather than retyped:
/// hand-authored DDL is the weak point of this test style. (It bit once: this
/// DDL declared a `show_preferences.updated_at_ms` that the real v13 never had,
/// so the tests protecting the riskiest code were checked against fiction. The
/// "fresh == upgraded" test at the bottom is the schema-dump artefact that
/// makes such a slip detectable.)
const _v13Ddl = '''
CREATE TABLE series_cache (anilist_id INTEGER NOT NULL, id_mal INTEGER,
  romaji TEXT, english TEXT, native_title TEXT, format TEXT,
  episode_count INTEGER, cover_image_url TEXT, cover_image_path TEXT,
  PRIMARY KEY (anilist_id));
CREATE TABLE file_cache (folder_path TEXT NOT NULL, relative_path TEXT NOT NULL,
  file_size INTEGER NOT NULL, modified_at_ms INTEGER NOT NULL, anilist_id INTEGER,
  episode_number INTEGER, parsed_title TEXT NOT NULL,
  match_score REAL NOT NULL DEFAULT 0, release_group TEXT,
  pending_identification INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (folder_path, relative_path));
CREATE TABLE library_folders (path TEXT NOT NULL, added_at_ms INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0, volume_id TEXT, volume_subpath TEXT,
  PRIMARY KEY (path));
CREATE TABLE match_overrides (file_size INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL, anilist_id INTEGER NOT NULL,
  anchored_episode INTEGER, continuous_offset INTEGER NOT NULL DEFAULT 0,
  display_continuous INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (file_size, modified_at_ms));
CREATE TABLE watch_state (anilist_id INTEGER NOT NULL, episode INTEGER NOT NULL,
  resume_position_ms INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0, watched INTEGER NOT NULL DEFAULT 0,
  watched_manual INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id, episode));
CREATE TABLE source_overrides (anilist_id INTEGER NOT NULL,
  episode INTEGER NOT NULL, folder_path TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id, episode));
CREATE TABLE skip_segments (anilist_id INTEGER NOT NULL, episode INTEGER NOT NULL,
  intro_start_ms INTEGER, intro_end_ms INTEGER, outro_start_ms INTEGER,
  outro_end_ms INTEGER, PRIMARY KEY (anilist_id, episode));
CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL,
  PRIMARY KEY (key));
CREATE TABLE hidden_episodes (anilist_id INTEGER NOT NULL,
  episode INTEGER NOT NULL, hidden_at_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (anilist_id, episode));
CREATE TABLE show_preferences (anilist_id INTEGER NOT NULL,
  picture_mode TEXT NOT NULL DEFAULT 'normal',
  next_episode_hidden INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id));
''';

/// The v1 schema, verbatim from the first commit that had a cache: two tables,
/// `anilist_id` everywhere, an absolute-path `file_cache`, no `id_mal`. The
/// earliest possible start, and the one whose upgrade used to abort — the v2
/// step emits `library_folders` in its CURRENT shape, so the v4 `addColumn
/// sort_order` that followed was a duplicate-column error.
const _v1Ddl = '''
CREATE TABLE series_cache (anilist_id INTEGER NOT NULL,
  romaji TEXT, english TEXT, native_title TEXT, format TEXT,
  episode_count INTEGER, cover_image_url TEXT, cover_image_path TEXT,
  PRIMARY KEY (anilist_id));
CREATE TABLE file_cache (path TEXT NOT NULL, file_size INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL, anilist_id INTEGER, episode_number INTEGER,
  parsed_title TEXT NOT NULL, match_score REAL NOT NULL DEFAULT 0,
  release_group TEXT, PRIMARY KEY (path));
''';

/// v4: v1 plus library_folders (with sort_order, v4's own addition) and
/// match_overrides. The other start that used to abort: the v5 step emits
/// watch_state with `watched_manual`, then v12 tried to add it again.
const _v4Ddl =
    '''
$_v1Ddl
CREATE TABLE library_folders (path TEXT NOT NULL, added_at_ms INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (path));
CREATE TABLE match_overrides (file_size INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL, anilist_id INTEGER NOT NULL,
  anchored_episode INTEGER, continuous_offset INTEGER NOT NULL DEFAULT 0,
  display_continuous INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (file_size, modified_at_ms));
''';

/// The v8 schema: absolute-path file_cache, no pending_identification, no
/// hidden_episodes, no show_preferences. Exists to exercise the LEAPFROG.
const _v8Ddl = '''
CREATE TABLE series_cache (anilist_id INTEGER NOT NULL, id_mal INTEGER,
  romaji TEXT, english TEXT, native_title TEXT, format TEXT,
  episode_count INTEGER, cover_image_url TEXT, cover_image_path TEXT,
  PRIMARY KEY (anilist_id));
CREATE TABLE file_cache (path TEXT NOT NULL, file_size INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL, anilist_id INTEGER, episode_number INTEGER,
  parsed_title TEXT NOT NULL, match_score REAL NOT NULL DEFAULT 0,
  release_group TEXT, PRIMARY KEY (path));
CREATE TABLE library_folders (path TEXT NOT NULL, added_at_ms INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (path));
CREATE TABLE match_overrides (file_size INTEGER NOT NULL,
  modified_at_ms INTEGER NOT NULL, anilist_id INTEGER NOT NULL,
  anchored_episode INTEGER, continuous_offset INTEGER NOT NULL DEFAULT 0,
  display_continuous INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (file_size, modified_at_ms));
CREATE TABLE watch_state (anilist_id INTEGER NOT NULL, episode INTEGER NOT NULL,
  resume_position_ms INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0, watched INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id, episode));
CREATE TABLE source_overrides (anilist_id INTEGER NOT NULL,
  episode INTEGER NOT NULL, folder_path TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id, episode));
CREATE TABLE skip_segments (anilist_id INTEGER NOT NULL, episode INTEGER NOT NULL,
  intro_start_ms INTEGER, intro_end_ms INTEGER, outro_start_ms INTEGER,
  outro_end_ms INTEGER, PRIMARY KEY (anilist_id, episode));
CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL,
  PRIMARY KEY (key));
''';

/// v13 -> v14 renames `anilist_id` to `series_id` across EIGHT tables, four of
/// which hold sacred user data. The rename is schema-text-only (SQLite rewrites
/// the stored CREATE TABLE and touches zero rows), so the guarantee under test
/// is total preservation: every row, every field, byte for byte.
///
/// It has outgrown its name: opening a seeded cache runs the migration to the
/// CURRENT schemaVersion, so every case here exercises v13 -> v18 end to end,
/// and the later versions are asserted at the bottom. There is deliberately no
/// separate v15/v16/v17/v18 file — a per-version file would re-run this same
/// chain and assert one more column, while the failures that actually happen
/// here are about which STARTING version you come from. Those get their own
/// cases instead (the v8 and v16 leapfrogs).
void main() {
  /// Every sacred table populated with DISTINCTIVE, NON-DEFAULT values — a row
  /// that survives by accident (defaults, zeroes) would prove nothing.
  CacheDatabase openMigratedV13() => CacheDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        final v = raw.select('PRAGMA user_version').first.values.first as int;
        if (v != 0) return;
        raw.execute(_v13Ddl);
        raw.execute(
          "INSERT INTO series_cache (anilist_id, id_mal, romaji, english, "
          "format, episode_count, cover_image_path) "
          "VALUES (21, 4224, 'Cowboy Bebop', 'Cowboy Bebop', 'TV', 26, '/a/21.jpg')",
        );
        raw.execute(
          "INSERT INTO series_cache (anilist_id, romaji) VALUES (99, 'No Mal')",
        );
        raw.execute(
          "INSERT INTO file_cache (folder_path, relative_path, file_size, "
          "modified_at_ms, anilist_id, episode_number, parsed_title) "
          "VALUES ('/lib', 'cb-01.mkv', 111, 222, 21, 1, 'Cowboy Bebop')",
        );
        raw.execute(
          'INSERT INTO match_overrides (file_size, modified_at_ms, anilist_id, '
          'anchored_episode, continuous_offset, display_continuous) '
          'VALUES (111, 222, 21, 7, 12, 1)',
        );
        raw.execute(
          'INSERT INTO watch_state (anilist_id, episode, resume_position_ms, '
          'duration_ms, watched, watched_manual, updated_at_ms) '
          'VALUES (21, 3, 987654, 1440000, 1, 1, 55)',
        );
        raw.execute(
          "INSERT INTO source_overrides (anilist_id, episode, folder_path, "
          "updated_at_ms) VALUES (21, 3, '/other/drive', 66)",
        );
        raw.execute(
          'INSERT INTO skip_segments (anilist_id, episode, intro_start_ms, '
          'intro_end_ms, outro_start_ms, outro_end_ms) '
          'VALUES (21, 3, 1000, 91000, 1330000, 1421000)',
        );
        raw.execute(
          'INSERT INTO hidden_episodes (anilist_id, episode, hidden_at_ms) '
          'VALUES (21, 9, 77)',
        );
        raw.execute(
          "INSERT INTO show_preferences (anilist_id, picture_mode, "
          "next_episode_hidden) VALUES (21, 'blur', 1)",
        );
        // Without this drift sees a brand-new database and runs onCreate, so
        // the migration under test never executes.
        raw.execute('PRAGMA user_version = 13');
      },
    ),
  );

  test('every sacred row survives the rename, field for field', () async {
    final db = openMigratedV13();
    addTearDown(db.close);

    // match_overrides — a fix-match, with its continuous-numbering settings.
    final override = (await db.allOverrideRows()).single;
    expect(override.seriesId, 21);
    expect(override.anchoredEpisode, 7);
    expect(override.continuousOffset, 12);
    expect(override.displayContinuous, isTrue);

    // watch_state — resume position AND the sticky manual flag.
    final watch = (await db.allWatchStateRows()).single;
    expect(watch.seriesId, 21);
    expect(watch.episode, 3);
    expect(watch.resumePositionMs, 987654);
    expect(watch.durationMs, 1440000);
    expect(watch.watched, isTrue);
    expect(watch.watchedManual, isTrue);

    // skip_segments — all four windows.
    final skip = (await db.allSkipAnswers()).single;
    expect(skip.seriesId, 21);
    expect(skip.introStartMs, 1000);
    expect(skip.introEndMs, 91000);
    expect(skip.outroStartMs, 1330000);
    expect(skip.outroEndMs, 1421000);

    // series_cache / file_cache.
    final series = (await db.allSeriesRows()).firstWhere(
      (r) => r.seriesId == 21,
    );
    expect(series.romaji, 'Cowboy Bebop');
    expect(series.coverImagePath, '/a/21.jpg', reason: 'art path untouched');
    final file = (await db.allFileRows()).single;
    expect(file.seriesId, 21);
    expect(file.relativePath, 'cb-01.mkv');
  });

  test('hidden episodes and show preferences survive', () async {
    final db = openMigratedV13();
    addTearDown(db.close);

    final hidden = (await db.hiddenRowsFor(21)).single;
    expect(hidden.episode, 9);
    expect(hidden.hiddenAtMs, 77);

    final prefs = await db.showPrefFor(21);
    expect(prefs?.pictureMode, 'blur');
    expect(prefs?.nextEpisodeHidden, isTrue);
  });

  test('row counts are unchanged — nothing dropped anywhere', () async {
    final db = openMigratedV13();
    addTearDown(db.close);

    Future<int> count(String t) async =>
        (await db.customSelect('SELECT COUNT(*) AS c FROM $t').getSingle())
            .read<int>('c');

    expect(await count('series_cache'), 2);
    expect(await count('file_cache'), 1);
    expect(await count('match_overrides'), 1);
    expect(await count('watch_state'), 1);
    expect(await count('source_overrides'), 1);
    expect(
      await count('skip_source_answers'),
      1,
      reason: 'v19 carries the skip row over as that source\'s answer',
    );
    expect(await count('hidden_episodes'), 1);
    expect(await count('show_preferences'), 1);
  });

  test('external ids are seeded from what the cache already knew', () async {
    final db = openMigratedV13();
    addTearDown(db.close);

    // Every pre-existing series_id WAS an AniList id — that is the invariant
    // the rename preserves, so it can be published as one.
    final ids = await db.externalIdsBySeriesId();
    expect(ids[21]?.anilist, 21);
    expect(ids[99]?.anilist, 99);
    expect(ids[21]?.mal, 4224);
    expect(ids[99]?.mal, isNull, reason: 'that series had no id_mal');

    final mal = await db
        .customSelect(
          "SELECT series_id, external_id FROM series_external_ids "
          "WHERE provider = 'mal'",
        )
        .get();
    expect(mal.length, 1, reason: 'only the series with an id_mal');
    expect(mal.single.read<int>('series_id'), 21);
    expect(mal.single.read<String>('external_id'), '4224');
  });

  test(
    'the split-brain guard exists: (provider, external_id) is UNIQUE',
    () async {
      final db = openMigratedV13();
      addTearDown(db.close);

      // Two series claiming the same AniList id is the shape that would strand
      // watch progress under an orphaned id. It must fail loudly, not silently.
      await expectLater(
        db.customStatement(
          "INSERT INTO series_external_ids (series_id, provider, external_id) "
          "VALUES (99, 'anilist', '21')",
        ),
        throwsA(anything),
      );
    },
  );

  test('v16/v17 add skip provenance and per-window confidence, without '
      'disturbing existing rows', () async {
    final db = openMigratedV13();
    addTearDown(db.close);

    final skip = (await db.allSkipAnswers()).single;
    expect(skip.introEndMs, 91000, reason: 'the window itself is untouched');
    // v19 turns each stored window into that source's ANSWER. This one was
    // written before v16 recorded provenance, so it becomes `legacy`: still
    // usable, but it can never outrank a known source or vote on agreement,
    // because we cannot say who produced it.
    expect(skip.source, kLegacySource);
  });

  test("v17 leaves no orphan of v16's replaced confidence column", () async {
    // The upgrade a real cache takes: v16 ADDS `confidence` on the way through
    // and v17 replaces it with a verdict per window. Guarding the drop on
    // "came from v16 or later" left the column behind on exactly this path,
    // which a single-hop test would never have shown.
    final db = openMigratedV13();
    addTearDown(db.close);

    // v19 retires skip_segments entirely, so the orphan cannot survive by
    // construction — what this now guards is that the whole v16→v17→v19
    // sequence RUNS on the path a real cache takes, and that the row arrives.
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(tables, isNot(contains('skip_segments')));
    expect(tables, contains('skip_source_answers'));
    expect((await db.allSkipAnswers()).single.introEndMs, 91000);
  });

  test(
    'v18 adds the skip resolution key, empty on every existing row',
    () async {
      // Empty MEANS "unknown inputs", so a migrated row is re-resolved once on
      // the next refresh and then left alone. Backfilling it to whatever the
      // current settings happen to be would assert that rows written before the
      // rule existed already satisfy it, and freeze them as they are forever.
      final db = openMigratedV13();
      addTearDown(db.close);

      final skip = (await db.allSkipAnswers()).single;
      expect(skip.introEndMs, 91000, reason: 'the window is still untouched');
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='skip_segments'",
            )
            .get(),
        isEmpty,
        reason: 'v19 retires the table once its rows have been carried over',
      );
    },
  );

  test('LEAPFROG v16 -> v18: the confidence drop still runs', () async {
    // The one starting version no other case covers. From 16, the `from < 16`
    // block is SKIPPED — `confidence` is already there from the real v16
    // migration — so v17's drop is the only thing that can remove it. This is
    // the same class of mistake as the guard that shipped wrong (`from >= 16`
    // left the orphan behind); it just fails from a different direction.
    final db = CacheDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          final v = raw.select('PRAGMA user_version').first.values.first as int;
          if (v != 0) return;
          raw.execute(_v13Ddl);
          // Bring the seeded v13 DDL up to the v16 shape by hand: the rename
          // plus the two columns v16 added.
          for (final t in const [
            'series_cache',
            'file_cache',
            'match_overrides',
            'watch_state',
            'source_overrides',
            'skip_segments',
            'hidden_episodes',
            'show_preferences',
          ]) {
            raw.execute('ALTER TABLE $t RENAME COLUMN anilist_id TO series_id');
          }
          raw.execute('ALTER TABLE series_cache DROP COLUMN id_mal');
          raw.execute(
            'CREATE TABLE series_external_ids (series_id INTEGER NOT NULL, '
            'provider TEXT NOT NULL, external_id TEXT NOT NULL, '
            'PRIMARY KEY (series_id, provider), UNIQUE (provider, external_id))',
          );
          raw.execute(
            "ALTER TABLE skip_segments ADD COLUMN source TEXT NOT NULL "
            "DEFAULT ''",
          );
          raw.execute(
            'ALTER TABLE skip_segments ADD COLUMN confidence INTEGER NOT NULL '
            'DEFAULT 0',
          );
          raw.execute(
            'INSERT INTO skip_segments (series_id, episode, intro_start_ms, '
            "intro_end_ms, source) VALUES (21, 3, 1000, 91000, 'aniskip')",
          );
          raw.execute('PRAGMA user_version = 16');
        },
      ),
    );
    addTearDown(db.close);

    // v19 retires skip_segments, so what a v16 START must prove is that the
    // whole v17 → v19 sequence runs and the row survives the hand-off.
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(tables, isNot(contains('skip_segments')));
    expect(tables, contains('skip_source_answers'));

    final skip = (await db.allSkipAnswers()).single;
    expect(skip.source, 'aniskip', reason: 'v16 provenance survives to v19');
    expect(skip.introEndMs, 91000);
  });

  test('LEAPFROG v8 -> v14 works (no such column: anilist_id)', () async {
    // The hazard: earlier migration steps call m.createTable(), which emits the
    // table in its CURRENT shape — already `series_id`. Renaming it again fails.
    // Every existing migration test covers exactly one hop, so nothing else in
    // the suite would catch this.
    final db = CacheDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          final v = raw.select('PRAGMA user_version').first.values.first as int;
          if (v != 0) return;
          raw.execute(_v8Ddl);
          raw.execute('PRAGMA user_version = 8');
          raw.execute(
            "INSERT INTO library_folders (path, added_at_ms) VALUES ('/lib', 1)",
          );
          raw.execute(
            "INSERT INTO series_cache (anilist_id, romaji) VALUES (21, 'Bebop')",
          );
          raw.execute(
            "INSERT INTO file_cache (path, file_size, modified_at_ms, "
            "anilist_id, episode_number, parsed_title) "
            "VALUES ('/lib/cb-01.mkv', 111, 222, 21, 1, 'Cowboy Bebop')",
          );
          raw.execute(
            'INSERT INTO watch_state (anilist_id, episode, resume_position_ms, '
            'duration_ms, watched, updated_at_ms) VALUES (21, 1, 4242, 100, 0, 9)',
          );
        },
      ),
    );
    addTearDown(db.close);

    // Reaching this line at all is most of the point.
    final watch = (await db.allWatchStateRows()).single;
    expect(watch.seriesId, 21);
    expect(watch.resumePositionMs, 4242, reason: 'carried across five hops');

    final file = (await db.allFileRows()).single;
    expect(file.seriesId, 21);
    expect(file.folderPath, '/lib', reason: 'v9 rebasing still applied');
    expect(file.relativePath, 'cb-01.mkv');
  });

  group('the chain is ATOMIC and refuses newer caches', () {
    // Drift does not wrap onUpgrade in a transaction and stamps the version
    // last, so before the wrapper a crash between two statements left a
    // half-migrated database still at the OLD version; every later launch
    // replayed the same step against the new shape, failed, and drift's sticky
    // migration error refused every open for the process. These pin the two
    // guarantees that replace that: nothing changes unless everything does, and
    // a cache from a newer build is refused before any statement runs.

    /// A v18-shaped database with skip_segments DELIBERATELY MISSING, so the
    /// v19 backfill's `INSERT … FROM skip_segments` throws mid-step — after
    /// createTable(skip_source_answers) has already run. Built from the v13
    /// DDL by hand, the same way the v16 leapfrog builds its start.
    void seedBrokenV18(dynamic raw) {
      raw.execute(_v13Ddl);
      for (final t in const [
        'series_cache',
        'file_cache',
        'match_overrides',
        'watch_state',
        'source_overrides',
        'skip_segments',
        'hidden_episodes',
        'show_preferences',
      ]) {
        raw.execute('ALTER TABLE $t RENAME COLUMN anilist_id TO series_id');
      }
      raw.execute('ALTER TABLE series_cache DROP COLUMN id_mal');
      raw.execute(
        'CREATE TABLE series_external_ids (series_id INTEGER NOT NULL, '
        'provider TEXT NOT NULL, external_id TEXT NOT NULL, '
        'PRIMARY KEY (series_id, provider), UNIQUE (provider, external_id))',
      );
      raw.execute('DROP TABLE skip_segments'); // the sabotage
      raw.execute(
        "INSERT INTO series_cache (series_id, romaji) VALUES (21, 'Bebop')",
      );
      raw.execute(
        'INSERT INTO watch_state (series_id, episode, resume_position_ms, '
        'duration_ms, watched, watched_manual, updated_at_ms) '
        'VALUES (21, 3, 987654, 1440000, 1, 1, 55)',
      );
      raw.execute('PRAGMA user_version = 18');
    }

    test('a step that fails mid-chain leaves the database UNTOUCHED', () async {
      final dir = await Directory.systemTemp.createTemp('anilocal_atomic_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      late List<Map<String, Object?>> Function(String) rawQuery;

      final broken = CacheDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            final v = raw.select('PRAGMA user_version').first.values.first;
            if (v == 0) seedBrokenV18(raw);
            rawQuery = (sql) => raw.select(sql).map((r) => r).toList();
          },
        ),
      );

      await expectLater(broken.allSeriesRows(), throwsA(anything));

      // The v19 step got as far as creating its new table before the backfill
      // threw. Without the transaction that table would now exist alongside an
      // unchanged version number — the half-migrated state that bricked the
      // cache. With it, nothing happened.
      expect(
        rawQuery('PRAGMA user_version').single.values.first,
        18,
        reason: 'version must not advance when the chain failed',
      );
      final tables = rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ).map((r) => r['name']).toSet();
      expect(
        tables,
        isNot(contains('skip_source_answers')),
        reason: 'the step that ran before the failure was rolled back',
      );
      expect(
        rawQuery('SELECT resume_position_ms FROM watch_state').single.values,
        [987654],
        reason: 'user data is exactly as it was',
      );
      await broken.close();

      // Repair the underlying file (restore the table the sabotage removed)
      // and open again: a clean retry from a clean state must succeed. This is
      // the whole point — the failure is recoverable, not sticky on disk.
      final repaired = CacheDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            final v = raw.select('PRAGMA user_version').first.values.first;
            if (v == 18) {
              raw.execute(
                'CREATE TABLE skip_segments (series_id INTEGER NOT NULL, '
                'episode INTEGER NOT NULL, intro_start_ms INTEGER, '
                'intro_end_ms INTEGER, outro_start_ms INTEGER, '
                'outro_end_ms INTEGER, '
                "source TEXT NOT NULL DEFAULT '', "
                'intro_confidence INTEGER NOT NULL DEFAULT 0, '
                'outro_confidence INTEGER NOT NULL DEFAULT 0, '
                "resolved_key TEXT NOT NULL DEFAULT '', "
                'PRIMARY KEY (series_id, episode))',
              );
            }
          },
        ),
      );
      addTearDown(repaired.close);
      expect((await repaired.allSeriesRows()).single.romaji, 'Bebop');
      expect(
        (await repaired.select(repaired.watchStates).get())
            .single
            .resumePositionMs,
        987654,
      );
    });

    test(
      'a cache from a NEWER build is refused, and its version untouched',
      () async {
        late List<Map<String, Object?>> Function(String) rawQuery;
        final db = CacheDatabase(
          NativeDatabase.memory(
            setup: (raw) {
              final v = raw.select('PRAGMA user_version').first.values.first;
              if (v == 0) {
                raw.execute(_v13Ddl);
                raw.execute('PRAGMA user_version = 99');
              }
              rawQuery = (sql) => raw.select(sql).map((r) => r).toList();
            },
          ),
        );
        addTearDown(db.close);

        await expectLater(
          db.allSeriesRows(),
          throwsA(isA<CacheNewerThanAppException>()),
        );
        // Drift treats a downgrade as an "upgrade" and would have re-stamped 99
        // down to 19 after running nothing — leaving the schema at 99's shape
        // with a 19 label, so the next real upgrade would fail. Refusing before
        // any statement keeps the label honest.
        expect(rawQuery('PRAGMA user_version').single.values.first, 99);
      },
    );
  });

  group('every starting version reaches v19', () {
    /// Opens a database seeded with [ddl] at [version], plus one series row
    /// and one path-keyed file row (both present since v1), and migrates it.
    CacheDatabase openFrom(String ddl, int version) => CacheDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          final v = raw.select('PRAGMA user_version').first.values.first;
          if (v != 0) return;
          raw.execute(ddl);
          raw.execute(
            "INSERT INTO series_cache (anilist_id, romaji) VALUES (21, 'Bebop')",
          );
          raw.execute(
            'INSERT INTO file_cache (path, file_size, modified_at_ms, '
            'anilist_id, episode_number, parsed_title) '
            "VALUES ('/lib/cb-01.mkv', 111, 222, 21, 1, 'Cowboy Bebop')",
          );
          raw.execute('PRAGMA user_version = $version');
        },
      ),
    );

    for (final (label, ddl, version) in [
      ('v1 — the very first cache', _v1Ddl, 1),
      ('v4 — watch_state not yet created', _v4Ddl, 4),
    ]) {
      test(
        'LEAPFROG $label -> v19 (used to abort on a duplicate column)',
        () async {
          // The v2 and v5 steps emit library_folders and watch_state in their
          // CURRENT shape; the later addColumn steps for sort_order, volume_id,
          // volume_subpath and watched_manual then collided. The chain must now
          // run end to end and carry the two seeded rows across.
          final db = openFrom(ddl, version);
          addTearDown(db.close);

          expect((await db.allSeriesRows()).single.romaji, 'Bebop');
          final f = (await db.allFileRows()).single;
          expect(f.seriesId, 21, reason: 'anilist_id -> series_id survived');
          expect(f.relativePath, 'cb-01.mkv', reason: 'v9 rebased the path');
        },
      );
    }

    test('an UPGRADED database has exactly the schema of a FRESH one', () async {
      // The schema-dump artefact this repo never had. Column ORDER may differ
      // (ALTER appends), so compare each table's columns as a set of
      // (name, type, notnull, default, pk) — anything else is a fork: a column
      // one install has and the other doesn't, or a table left behind.
      Future<Map<String, Set<String>>> schemaOf(CacheDatabase db) async {
        final tables =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type='table' "
                      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toList();
        final out = <String, Set<String>>{};
        for (final t in tables) {
          final cols = await db
              .customSelect(
                "SELECT name, type, \"notnull\", dflt_value, pk "
                "FROM pragma_table_info('$t')",
              )
              .get();
          out[t] = {
            for (final c in cols)
              '${c.read<String>('name')}|${c.read<String>('type')}|'
                  '${c.read<int>('notnull')}|${c.readNullable<String>('dflt_value')}|'
                  '${c.read<int>('pk')}',
          };
        }
        return out;
      }

      final fresh = CacheDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final upgraded = openFrom(_v1Ddl, 1);
      addTearDown(upgraded.close);

      final a = await schemaOf(fresh);
      final b = await schemaOf(upgraded);
      expect(
        b.keys.toSet(),
        a.keys.toSet(),
        reason: 'same set of tables — no orphan left behind by the chain',
      );
      for (final t in a.keys) {
        expect(
          b[t],
          a[t],
          reason: 'columns of $t differ between fresh and upgraded',
        );
      }
    });
  });
}
