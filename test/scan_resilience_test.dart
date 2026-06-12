import 'dart:convert';
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

http.Response _page(List<Map<String, dynamic>> media) => http.Response(
  jsonEncode({
    'data': {
      'Page': {'media': media},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _m(int id, String romaji) => {
  'id': id,
  'idMal': null,
  'title': {'romaji': romaji, 'english': null, 'native': null},
  'format': 'TV',
  'episodes': 26,
  'coverImage': {'extraLarge': 'http://a/$id.jpg'},
  'relations': {'edges': []},
};

void main() {
  late Directory dir;
  late CacheDatabase db;
  late DriftLibraryRepository repo;
  late LibrarySync sync;
  var anilistDown = false;

  Future<void> touch(String name, int size) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    await f.writeAsString('x' * size);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_resil_');
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    anilistDown = false;
    final artDir = await Directory('${dir.path}/.art').create();
    final mock = MockClient((req) async {
      if (req.method == 'POST') {
        if (anilistDown) return http.Response('forbidden', 403);
        final q = (jsonDecode(req.body)['variables']['search'] as String)
            .toLowerCase();
        if (q.contains('cowboy')) return _page([_m(1, 'Cowboy Bebop')]);
        if (q.contains('trigun')) return _page([_m(2, 'Trigun')]);
        return _page(const []);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    sync = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
      cache: db,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
      aniSkip: AniSkipClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'all-lookups-failing scan preserves the cached library (no wipe)',
    () async {
      // Healthy scan populates the cache.
      await touch('Cowboy Bebop - 01.mkv', 100);
      await touch('Cowboy Bebop - 02.mkv', 200);
      await sync.sync([dir.path]);
      expect((await repo.allSeries()).length, 1);
      expect((await repo.episodesFor(1)).length, 2);

      // Library reorganized (old files gone) AND AniList is down: the one new
      // title needs a lookup, which 403s — so every attempted lookup fails.
      await File('${dir.path}/Cowboy Bebop - 01.mkv').delete();
      await File('${dir.path}/Cowboy Bebop - 02.mkv').delete();
      await touch('Trigun - 01.mkv', 300);
      anilistDown = true;

      final summary = await sync.sync([dir.path]);

      expect(summary.apiUnreachable, isTrue);
      expect(summary.removed, 0, reason: 'an outage must remove nothing');
      expect(
        (await repo.allSeries()).length,
        1,
        reason: 'series preserved through the outage, not pruned',
      );
      expect(
        (await repo.episodesFor(1)).length,
        2,
        reason: 'cached episodes preserved, not emptied',
      );
    },
  );

  test('a healthy scan still removes a genuinely-gone file', () async {
    // The resilience guard must NOT block normal removals when the API is fine.
    await touch('Cowboy Bebop - 01.mkv', 100);
    await touch('Cowboy Bebop - 02.mkv', 200);
    await sync.sync([dir.path]);
    expect((await repo.episodesFor(1)).length, 2);

    await File('${dir.path}/Cowboy Bebop - 01.mkv').delete();
    final summary = await sync.sync([dir.path]); // API up

    expect(summary.apiUnreachable, isFalse);
    expect(summary.removed, 1);
    expect((await repo.episodesFor(1)).length, 1, reason: 'gone file removed');
  });
}
