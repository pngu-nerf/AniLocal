import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The complete v8 schema (pre stable-volume-identity): file_cache keyed by an
/// absolute `path`, library_folders with no volume binding. Authored by hand so
/// the test can open a populated v8 cache and exercise the real v8 -> v9
/// migration. Defaults/PKs mirror drift's generated DDL.
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

void main() {
  late Directory dir;
  late String mount; // a real dir standing in for the (still-mounted) volume

  // Real files on disk, so a post-migration rescan can confirm "unchanged".
  late int size1, mtime1;

  Future<void> touch(String path, int size) async {
    final f = File(path);
    await f.create(recursive: true);
    await f.writeAsString('x' * size);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_mig_');
    mount = '${dir.path}/Anime';
    await touch('$mount/Cowboy Bebop/Cowboy Bebop - 01.mkv', 123);
    final st = await File('$mount/Cowboy Bebop/Cowboy Bebop - 01.mkv').stat();
    size1 = st.size;
    mtime1 = st.modified.millisecondsSinceEpoch;
  });

  tearDown(() async => dir.delete(recursive: true));

  /// A v8 database, populated, opened through the real v9 migration.
  CacheDatabase openMigratedV8() => CacheDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        final v = raw.select('PRAGMA user_version').first.values.first as int;
        if (v != 0) return; // already migrated within this connection
        raw.execute(_v8Ddl);
        raw.execute(
          "INSERT INTO library_folders (path, added_at_ms, sort_order) "
          "VALUES ('$mount', 0, 0)",
        );
        raw.execute(
          "INSERT INTO series_cache (anilist_id, romaji, format, episode_count) "
          "VALUES (1, 'Cowboy Bebop', 'TV', 26)",
        );
        // An absolute-path file row (the v8 identity).
        raw.execute(
          "INSERT INTO file_cache (path, file_size, modified_at_ms, anilist_id, "
          "episode_number, parsed_title, match_score, release_group) VALUES "
          "('$mount/Cowboy Bebop/Cowboy Bebop - 01.mkv', $size1, $mtime1, 1, 1, "
          "'Cowboy Bebop', 1.0, NULL)",
        );
        // Watch state + a fix-match override that MUST survive the migration.
        raw.execute(
          "INSERT INTO watch_state (anilist_id, episode, resume_position_ms, "
          "watched, updated_at_ms) VALUES (1, 1, 5000, 0, 7)",
        );
        raw.execute(
          "INSERT INTO match_overrides (file_size, modified_at_ms, anilist_id, "
          "anchored_episode) VALUES (999, 888, 42, 3)",
        );
        raw.execute('PRAGMA user_version = 8');
      },
    ),
  );

  test(
    'rebases absolute paths to (folder, relative) and keeps watch/overrides',
    () async {
      final db = openMigratedV8();
      addTearDown(db.close);

      final files = await db.allFileRows();
      expect(files, hasLength(1));
      expect(files.single.folderPath, mount, reason: 'owning folder identity');
      expect(
        files.single.relativePath,
        'Cowboy Bebop/Cowboy Bebop - 01.mkv',
        reason: 'path rebased relative to its folder',
      );
      expect(files.single.anilistId, 1, reason: 'match preserved');
      expect(files.single.fileSize, size1);
      expect(files.single.modifiedAtMs, mtime1);

      // Untouched stores survive (they were never path-keyed).
      expect((await db.allWatchStateRows()).single.resumePositionMs, 5000);
      final ov = (await db.allOverrideRows()).single;
      expect((ov.fileSize, ov.modifiedAtMs, ov.anchoredEpisode), (999, 888, 3));

      // The new volume-binding columns exist and start null (backfilled on scan).
      expect((await db.allFolderRows()).single.volumeId, isNull);
    },
  );

  test(
    'first rescan after migrating is all-unchanged with zero AniList calls',
    () async {
      final db = openMigratedV8();
      addTearDown(db.close);
      final artDir = await Directory('${dir.path}/.art').create();
      // Any AniList POST would 500 — proving the rescan made none.
      final mock = MockClient(
        (req) async => req.method == 'POST'
            ? http.Response('nope', 500)
            : http.Response.bytes([1, 2, 3], 200),
      );
      final sync = LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
        cache: db,
        art: ArtCache(httpClient: mock, directory: () async => artDir),
        aniSkip: AniSkipClient(
          httpClient: MockClient((_) async => http.Response('', 404)),
        ),
      );

      final summary = await sync.sync([mount]);

      expect(
        summary.unchanged,
        1,
        reason: 'migrated row recognized as the file',
      );
      expect(summary.processed, 0, reason: 'nothing re-identified');
      expect(summary.anilistLookups, 0, reason: 'no AniList refetch — the fix');
      expect(summary.removed, 0);

      // And the library reads back, resolved to the real file.
      final repo = DriftLibraryRepository(db);
      final eps = await repo.episodesFor(1);
      expect(eps, hasLength(1));
      expect(File(eps.single.fileRef).existsSync(), isTrue);
    },
  );
}
