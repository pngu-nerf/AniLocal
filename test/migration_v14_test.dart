import 'package:anilocal/data/cache/cache_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The complete v13 schema — every table still keyed by `anilist_id`, plus
/// show_preferences. Copied forward from `migration_v13_test.dart`'s `_v12Ddl`
/// with the show_preferences table appended, deliberately rather than retyped:
/// hand-authored DDL is the weak point of this test style, and this repo has no
/// schema-dump artifacts to check it against.
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
  next_episode_hidden INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (anilist_id));
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
          "next_episode_hidden, updated_at_ms) VALUES (21, 'blur', 1, 88)",
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
    final skip = (await db.allSkipRows()).single;
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
    expect(await count('skip_segments'), 1);
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

    final skip = (await db.allSkipRows()).single;
    expect(skip.introEndMs, 91000, reason: 'the window itself is untouched');
    // Left EMPTY rather than backfilled to 'aniskip': "we don't know where this
    // came from" must stay distinguishable from "we recorded that it did".
    expect(skip.source, '');
    // v17 replaced v16's single verdict with one per window; both default to
    // `single`, which is what a row nothing has cross-checked should say.
    expect(skip.introConfidence, 0);
    expect(skip.outroConfidence, 0);
  });

  test("v17 leaves no orphan of v16's replaced confidence column", () async {
    // The upgrade a real cache takes: v16 ADDS `confidence` on the way through
    // and v17 replaces it with a verdict per window. Guarding the drop on
    // "came from v16 or later" left the column behind on exactly this path,
    // which a single-hop test would never have shown.
    final db = openMigratedV13();
    addTearDown(db.close);

    final columns = await db
        .customSelect("SELECT name FROM pragma_table_info('skip_segments')")
        .get();
    final names = columns.map((r) => r.read<String>('name')).toSet();

    expect(names, contains('intro_confidence'));
    expect(names, contains('outro_confidence'));
    expect(names, isNot(contains('confidence')));
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

      final skip = (await db.allSkipRows()).single;
      expect(skip.resolvedKey, '');
      expect(skip.introEndMs, 91000, reason: 'the window is still untouched');
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

    final names =
        (await db
                .customSelect(
                  "SELECT name FROM pragma_table_info('skip_segments')",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(names, isNot(contains('confidence')), reason: 'v17 dropped it');
    expect(names, containsAll(['intro_confidence', 'outro_confidence']));
    expect(names, contains('resolved_key'), reason: 'v18');

    final skip = (await db.allSkipRows()).single;
    expect(skip.source, 'aniskip', reason: 'v16 provenance survives');
    expect(skip.introEndMs, 91000);
    expect(skip.resolvedKey, '');
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
}
