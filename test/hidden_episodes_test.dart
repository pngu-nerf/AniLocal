import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A complete v10 schema (immediate-population; NO hidden_episodes table),
/// authored by hand so the test exercises the real v10 -> v11 migration against
/// a populated cache.
const _v10Ddl = '''
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
  group('hidden episodes — persistence & write API', () {
    late CacheDatabase db;
    late DriftLibraryRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = DriftLibraryRepository(db);
    });
    tearDown(() => db.close());

    test('hide / read / unhide, keyed per series', () async {
      await repo.hideEpisodes(10, [3, 4]);
      await repo.hideEpisodes(20, [7]);

      expect(await repo.hiddenEpisodes(10), {3, 4});
      expect(await repo.hiddenEpisodes(20), {7});
      expect(await repo.allHiddenEpisodes(), {
        10: {3, 4},
        20: {7},
      });

      await repo.unhideEpisodes(10, [3]);
      expect(await repo.hiddenEpisodes(10), {4});
    });

    test('hiding is idempotent', () async {
      await repo.hideEpisodes(10, [3]);
      await repo.hideEpisodes(10, [3, 5]);
      expect(await repo.hiddenEpisodes(10), {3, 5});
    });

    test('SACRED: a rescan (applySync) never wipes hidden state', () async {
      // A matched series with one file, and the user hides two missing eps.
      await db.upsertSeries(
        const CachedSeriesRow(anilistId: 10, romaji: 'Show', episodeCount: 5),
      );
      await db.upsertFiles(const [
        CachedFileRow(
          folderPath: '/lib',
          relativePath: 'e1.mkv',
          fileSize: 1,
          modifiedAtMs: 1,
          anilistId: 10,
          episodeNumber: 1,
          parsedTitle: 'Show',
          matchScore: 1,
          pendingIdentification: false,
        ),
      ]);
      await repo.hideEpisodes(10, [2, 3]);

      // A rescan removes the only file → applySync PRUNES series 10 from
      // series_cache. The hidden state must survive untouched (seam #5 — the
      // fill path has no writer for hidden_episodes), like watch-state.
      await db.applySync(
        seriesUpserts: const [],
        fileUpserts: const [],
        removedKeys: [('/lib', 'e1.mkv')],
      );

      expect(await db.allSeriesRows(), isEmpty); // series really was pruned
      expect(await repo.hiddenEpisodes(10), {2, 3}); // hidden survived
    });
  });

  group('v10 -> v11 migration', () {
    CacheDatabase openMigratedV10() => CacheDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          final v = raw.select('PRAGMA user_version').first.values.first as int;
          if (v != 0) return;
          raw.execute(_v10Ddl);
          raw.execute(
            "INSERT INTO series_cache (anilist_id, romaji, format, episode_count) "
            "VALUES (1, 'Cowboy Bebop', 'TV', 26)",
          );
          raw.execute(
            "INSERT INTO file_cache (folder_path, relative_path, file_size, "
            "modified_at_ms, anilist_id, episode_number, parsed_title, "
            "match_score, pending_identification) "
            "VALUES ('/lib', 'cb-01.mkv', 1, 1, 1, 1, 'Cowboy Bebop', 1.0, 0)",
          );
          raw.execute('PRAGMA user_version = 10');
        },
      ),
    );

    test('adds an empty hidden_episodes table; existing data intact', () async {
      final db = openMigratedV10();
      addTearDown(db.close);
      final repo = DriftLibraryRepository(db);

      // New table exists and is empty on an existing populated cache.
      expect(await db.allHiddenRows(), isEmpty);
      // Existing content untouched.
      final series = await repo.allSeries();
      expect(series.single.anilistId, 1);
      expect(series.single.episodeCount, 26);

      // And hiding works post-migration.
      await repo.hideEpisodes(1, [2]);
      expect(await repo.hiddenEpisodes(1), {2});
    });
  });
}
