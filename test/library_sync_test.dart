import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
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

http.Response _page(List<Map<String, dynamic>> media) => http.Response(
  jsonEncode({
    'data': {
      'Page': {'media': media},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _m(int id, String romaji, String cover) => {
  'id': id,
  'title': {'romaji': romaji, 'english': null, 'native': null},
  'format': 'TV',
  'episodes': 26,
  'coverImage': {'extraLarge': cover, 'large': cover, 'medium': cover},
};

void main() {
  late Directory dir;
  late CacheDatabase db;
  late LibrarySync sync;
  late DriftLibraryRepository repo;
  var anilistCalls = 0;

  Future<File> touch(String name, {String content = 'x'}) async {
    final f = File('${dir.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_sync_');
    anilistCalls = 0;
    db = CacheDatabase(NativeDatabase.memory());
    final artDir = await Directory('${dir.path}/art').create();

    final mock = MockClient((req) async {
      if (req.method == 'POST') {
        anilistCalls++;
        final search = (jsonDecode(req.body)['variables']['search']) as String;
        if (search.toLowerCase().contains('cowboy')) {
          return _page([_m(1, 'Cowboy Bebop', 'https://art.test/1.jpg')]);
        }
        return _page(const []); // no match
      }
      return http.Response.bytes([0, 1, 2, 3], 200); // art bytes
    });

    sync = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
      cache: db,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
    );
    repo = DriftLibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'first scan: matches one series, records the no-match, caches art',
    () async {
      await touch('Cowboy Bebop - 01.mkv');
      await touch('Totally Unknown Show - 01.mkv');

      final s = await sync.sync([dir.path]);

      expect(s.filesScanned, 2);
      expect(s.matched, 1);
      expect(s.unmatched, 1);

      final series = await repo.allSeries();
      expect(series.single.titles.romaji, 'Cowboy Bebop');
      // Art downloaded to a local file that exists.
      expect(series.single.coverImageRef, isNotNull);
      expect(File(series.single.coverImageRef!).existsSync(), isTrue);

      final unmatched = await repo.unmatchedFiles();
      expect(unmatched.single.parsedTitle, 'Totally Unknown Show');
    },
  );

  test(
    'rescan with no changes: nothing reprocessed, no AniList calls',
    () async {
      await touch('Cowboy Bebop - 01.mkv');
      await touch('Totally Unknown Show - 01.mkv');
      await sync.sync([dir.path]);
      final callsAfterFirst = anilistCalls;

      final s = await sync.sync([dir.path]);

      expect(s.unchanged, 2);
      expect(s.processed, 0);
      expect(anilistCalls, callsAfterFirst, reason: 'no refetch of unchanged');
      // The no-match file is still recorded, not vanished.
      expect((await repo.unmatchedFiles()).length, 1);
    },
  );

  test(
    'adding an episode of a known series: only that file, no AniList call',
    () async {
      await touch('Cowboy Bebop - 01.mkv');
      await sync.sync([dir.path]);
      final callsAfterFirst = anilistCalls;

      await touch('Cowboy Bebop - 02.mkv');
      final s = await sync.sync([dir.path]);

      expect(s.processed, 1);
      expect(s.unchanged, 1);
      expect(s.anilistLookups, 0, reason: 'known series reused from cache');
      expect(anilistCalls, callsAfterFirst);
      final episodes = await repo.episodesFor(1);
      expect(episodes.map((e) => e.number), [1, 2]);
    },
  );

  test('removing a file: cache updates, orphan series pruned', () async {
    final ep1 = await touch('Cowboy Bebop - 01.mkv');
    await sync.sync([dir.path]);
    expect((await repo.allSeries()).length, 1);

    await ep1.delete();
    final s = await sync.sync([dir.path]);

    expect(s.removed, 1);
    expect(
      await repo.allSeries(),
      isEmpty,
    ); // last episode gone -> series pruned
    expect(await repo.episodesFor(1), isEmpty);
  });

  test(
    'transient AniList error: file skipped, not cached as unmatched',
    () async {
      // A matcher whose search always throws (e.g. 429).
      final failing = LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          anilist: AniListClient(
            httpClient: MockClient((_) async => http.Response('boom', 500)),
          ),
        ),
        cache: db,
        art: ArtCache(
          httpClient: MockClient((_) async => http.Response.bytes([0], 200)),
          directory: () async => dir,
        ),
      );
      await touch('Cowboy Bebop - 01.mkv');

      final s = await failing.sync([dir.path]);

      expect(s.errored, 1);
      expect(s.matched, 0);
      expect(s.unmatched, 0);
      // Not recorded at all -> will be retried next scan, not stuck as unmatched.
      expect(await repo.unmatchedFiles(), isEmpty);
      expect(await repo.allSeries(), isEmpty);
    },
  );

  test(
    'unreadable watched folder: cached files preserved, surfaced loudly',
    () async {
      // Scan a subfolder, then make it unreadable (delete it) and rescan it.
      final libDir = await Directory('${dir.path}/lib').create();
      await File('${libDir.path}/Cowboy Bebop - 01.mkv').writeAsString('x');
      await sync.sync([libDir.path]);
      expect((await repo.allSeries()).length, 1);

      await libDir.delete(recursive: true); // folder vanished -> unreadable
      final s = await sync.sync([libDir.path]);

      expect(s.unreadableFolders, [libDir.path]);
      expect(
        s.removed,
        0,
        reason: 'do NOT delete files under an unreadable folder',
      );
      expect(
        (await repo.allSeries()).length,
        1,
        reason: 'cached items preserved',
      );
    },
  );
}
