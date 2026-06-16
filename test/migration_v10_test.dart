import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The complete v9 schema (pre immediate-population): file_cache keyed by
/// (folder_path, relative_path), library_folders with volume binding, and NO
/// pending_identification column. Authored by hand so the test exercises the
/// real v9 -> v10 migration against a populated cache.
const _v9Ddl = '''
CREATE TABLE series_cache (anilist_id INTEGER NOT NULL, id_mal INTEGER,
  romaji TEXT, english TEXT, native_title TEXT, format TEXT,
  episode_count INTEGER, cover_image_url TEXT, cover_image_path TEXT,
  PRIMARY KEY (anilist_id));
CREATE TABLE file_cache (folder_path TEXT NOT NULL, relative_path TEXT NOT NULL,
  file_size INTEGER NOT NULL, modified_at_ms INTEGER NOT NULL, anilist_id INTEGER,
  episode_number INTEGER, parsed_title TEXT NOT NULL,
  match_score REAL NOT NULL DEFAULT 0, release_group TEXT,
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

void main() {
  /// A populated v9 database, opened through the real v9 -> v10 migration.
  CacheDatabase openMigratedV9() => CacheDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        final v = raw.select('PRAGMA user_version').first.values.first as int;
        if (v != 0) return;
        raw.execute(_v9Ddl);
        raw.execute(
          "INSERT INTO library_folders (path, added_at_ms) VALUES ('/lib', 0)",
        );
        raw.execute(
          "INSERT INTO series_cache (anilist_id, romaji, format, episode_count) "
          "VALUES (1, 'Cowboy Bebop', 'TV', 26)",
        );
        // A MATCHED file...
        raw.execute(
          "INSERT INTO file_cache (folder_path, relative_path, file_size, "
          "modified_at_ms, anilist_id, episode_number, parsed_title, match_score) "
          "VALUES ('/lib', 'cb-01.mkv', 1, 1, 1, 1, 'Cowboy Bebop', 1.0)",
        );
        // ...and an UNMATCHED file (anilist_id NULL) — pre-v10 these were all
        // "confirmed unmatched", which the migration must preserve.
        raw.execute(
          "INSERT INTO file_cache (folder_path, relative_path, file_size, "
          "modified_at_ms, anilist_id, episode_number, parsed_title, match_score) "
          "VALUES ('/lib', 'mystery-01.mkv', 2, 2, NULL, 1, 'Mystery Show', 0)",
        );
        raw.execute('PRAGMA user_version = 9');
      },
    ),
  );

  test('v9 -> v10 adds pending_identification defaulting to false', () async {
    final db = openMigratedV9();
    addTearDown(db.close);

    final files = await db.allFileRows();
    expect(files, hasLength(2));
    // Every migrated row is NOT pending — matched rows are untouched and the
    // existing unmatched row stays confirmed-unmatched (its pre-v10 meaning),
    // never silently promoted to a retryable placeholder.
    expect(files.every((f) => f.pendingIdentification == false), isTrue);
  });

  test(
    'existing content is unaffected: matched grid + confirmed-unmatched',
    () async {
      final db = openMigratedV9();
      addTearDown(db.close);
      final repo = DriftLibraryRepository(db);

      // The matched series still shows in the grid (not as a placeholder).
      final series = await repo.allSeries();
      expect(series.single.anilistId, 1);
      expect(series.single.pending, isFalse);

      // The pre-existing unmatched file is still in the fix-match screen, and is
      // NOT surfaced as a pending placeholder.
      final unmatched = await repo.unmatchedFiles();
      expect(unmatched.single.parsedTitle, 'Mystery Show');
      expect(series.where((s) => s.pending), isEmpty);
    },
  );
}
