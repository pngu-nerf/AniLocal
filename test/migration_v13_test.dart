import 'package:anilocal/data/cache/cache_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The complete v12 schema (pre per-show preferences): everything through
/// watch_state.watched_manual, but NO show_preferences table. Authored by hand
/// so the test exercises the real v12 -> v13 migration against a POPULATED cache.
const _v12Ddl = '''
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
''';

void main() {
  /// A populated v12 database, opened through the real v12 -> v13 migration.
  CacheDatabase openMigratedV12() => CacheDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        final v = raw.select('PRAGMA user_version').first.values.first as int;
        if (v != 0) return;
        raw.execute(_v12Ddl);
        raw.execute(
          "INSERT INTO series_cache (anilist_id, romaji, format, episode_count) "
          "VALUES (1, 'Cowboy Bebop', 'TV', 26)",
        );
        raw.execute(
          'INSERT INTO watch_state (anilist_id, episode, resume_position_ms, '
          'duration_ms, watched, watched_manual, updated_at_ms) '
          'VALUES (1, 3, 0, 1440000, 1, 1, 5)',
        );
        raw.execute('PRAGMA user_version = 12');
      },
    ),
  );

  test('v12 -> v13 creates an empty show_preferences table', () async {
    final db = openMigratedV12();
    addTearDown(db.close);

    // The new table exists and starts empty — no show has an override yet.
    expect(await db.allShowPrefRows(), isEmpty);
  });

  test('existing content is untouched by the migration', () async {
    final db = openMigratedV12();
    addTearDown(db.close);

    final series = await db.allSeriesRows();
    expect(series.single.anilistId, 1);
    // The manual watched-override from v12 survives intact.
    final w = (await db.allWatchStateRows()).single;
    expect(w.watched, isTrue);
    expect(w.watchedManual, isTrue);
  });
}
