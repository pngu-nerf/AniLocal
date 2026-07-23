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
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _skipJson() => jsonEncode({
  'found': true,
  'results': [
    {
      'interval': {'startTime': 90.0, 'endTime': 110.0},
      'skipType': 'op',
      'skipId': 'a',
      'episodeLength': 1440.0,
    },
    {
      'interval': {'startTime': 1320.0, 'endTime': 1410.0},
      'skipType': 'ed',
      'skipId': 'b',
      'episodeLength': 1440.0,
    },
  ],
  'message': 'ok',
  'statusCode': 200,
});

http.Response _anilistPage() => http.Response(
  jsonEncode({
    'data': {
      'Page': {
        'media': [
          {
            'id': 1,
            'idMal': 999,
            'title': {
              'romaji': 'Cowboy Bebop',
              'english': null,
              'native': null,
            },
            'format': 'TV',
            'episodes': 26,
            'coverImage': {'extraLarge': 'http://a/1.jpg'},
            'relations': {'edges': []},
          },
        ],
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('AniSkipClient', () {
    test('parses op -> intro and ed -> outro', () async {
      final client = AniSkipClient(
        httpClient: MockClient((_) async => http.Response(_skipJson(), 200)),
      );
      final skips = await client.fetchSkips(999, 1);
      expect(skips, isNotNull);
      expect(
        skips!.intro,
        const SkipRange(
          start: Duration(seconds: 90),
          end: Duration(seconds: 110),
        ),
      );
      expect(
        skips.outro,
        const SkipRange(
          start: Duration(seconds: 1320),
          end: Duration(seconds: 1410),
        ),
      );
    });

    test('404 -> null (no data is normal, not an error)', () async {
      final client = AniSkipClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      expect(await client.fetchSkips(999, 1), isNull);
    });

    test('found:false -> null', () async {
      final client = AniSkipClient(
        httpClient: MockClient(
          (_) async =>
              http.Response(jsonEncode({'found': false, 'results': []}), 200),
        ),
      );
      expect(await client.fetchSkips(999, 1), isNull);
    });
  });

  group('sync caches skips; player reads them offline', () {
    late Directory dir;
    late CacheDatabase db;
    late DriftLibraryRepository repo;

    Future<void> touch(String name) async {
      final f = File('${dir.path}/$name');
      await f.create(recursive: true);
      await f.writeAsString('x' * 800);
    }

    LibrarySync syncWith(MockClient mock, Directory artDir) => LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
      cache: db,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
      aniSkip: AniSkipClient(httpClient: mock),
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_aniskip_');
      db = CacheDatabase(NativeDatabase.memory());
      repo = DriftLibraryRepository(db);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('AniSkip data is cached and rides on the Episode (+ idMal)', () async {
      final artDir = await Directory('${dir.path}/.art').create();
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage();
        if (req.url.host.contains('aniskip')) {
          return http.Response(_skipJson(), 200);
        }
        return http.Response.bytes([1, 2, 3], 200); // art
      });
      await touch('Cowboy Bebop - 03.mkv');

      await syncWith(mock, artDir).sync([dir.path]);

      final ep = (await repo.episodesFor(1)).firstWhere((e) => e.number == 3);
      expect(
        ep.introSkip,
        const SkipRange(
          start: Duration(seconds: 90),
          end: Duration(seconds: 110),
        ),
      );
      expect(ep.outroSkip, isNotNull);
      // idMal was fetched + cached (needed to query AniSkip).
      expect((await db.allSeriesRows()).single.idMal, 999);
    });

    test('no AniSkip data -> Episode has null skips (graceful)', () async {
      final artDir = await Directory('${dir.path}/.art').create();
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage();
        if (req.url.host.contains('aniskip')) return http.Response('', 404);
        return http.Response.bytes([1, 2, 3], 200);
      });
      await touch('Cowboy Bebop - 03.mkv');

      await syncWith(mock, artDir).sync([dir.path]);

      final ep = (await repo.episodesFor(1)).firstWhere((e) => e.number == 3);
      expect(ep.introSkip, isNull);
      expect(ep.outroSkip, isNull);
    });
  });

  group('refreshMetadata backfill', () {
    late Directory dir;
    late CacheDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_refresh_');
      db = CacheDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('backfills idMal + skips; leaves overrides and watch-state', () async {
      // Pre-v8 state: series cached with NO idMal, a matched file, plus a
      // watch-state row and a fix-match override that must survive.
      await db.applySync(
        seriesUpserts: [
          CachedSeriesRow(
            anilistId: 1,
            idMal: null,
            romaji: 'Cowboy Bebop',
            english: null,
            nativeTitle: null,
            format: 'TV',
            episodeCount: 26,
            coverImageUrl: null,
            coverImagePath: null,
          ),
        ],
        fileUpserts: [
          CachedFileRow(
            folderPath: '/lib',
            relativePath: 'cb-03.mkv',
            fileSize: 1,
            modifiedAtMs: 1,
            anilistId: 1,
            episodeNumber: 3,
            parsedTitle: 'Cowboy Bebop',
            matchScore: 1,
            releaseGroup: null,
            pendingIdentification: false,
          ),
        ],
        removedKeys: const [],
      );
      await db.upsertWatchState(
        WatchStateRow(
          anilistId: 1,
          episode: 3,
          resumePositionMs: 5000,
          durationMs: 0,
          watched: false,
          watchedManual: false,
          updatedAtMs: 1,
        ),
      );
      await db.upsertOverride(
        MatchOverrideRow(
          fileSize: 99,
          modifiedAtMs: 99,
          anilistId: 2,
          anchoredEpisode: 1,
          continuousOffset: 0,
          displayContinuous: false,
        ),
      );

      final artDir = await Directory('${dir.path}/.art').create();
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage(); // id 1, idMal 999
        if (req.url.host.contains('aniskip')) {
          return http.Response(_skipJson(), 200);
        }
        return http.Response.bytes([1, 2, 3], 200);
      });
      final sync = LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
        cache: db,
        art: ArtCache(httpClient: mock, directory: () async => artDir),
        aniSkip: AniSkipClient(httpClient: mock),
      );

      final result = await sync.refreshMetadata();

      expect(result.seriesRefreshed, 1);
      expect(result.skipsFetched, 1);
      // idMal backfilled onto the existing series row.
      expect((await db.allSeriesRows()).single.idMal, 999);
      // Skip data now cached for the matched episode.
      expect(await db.skipSegmentFor(1, 3), isNotNull);
      // User data untouched.
      expect((await db.watchStateFor(1, 3))!.resumePositionMs, 5000);
      expect((await db.allOverrideRows()).length, 1);
    });
  });
}
