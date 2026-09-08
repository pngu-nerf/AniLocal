import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/crossmap/cross_map_store.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// AniSkip is keyed by MAL id, and that id used to come ONLY from AniList's
/// `idMal`. So a show AniList returned without one — or a show identified while
/// AniList was degraded — silently lost auto-skip forever. This is the live
/// case: `SAKAMOTO DAYS Part 2` sits in the real cache with `id_mal` null while
/// the cross-map knows it is 60285.
///
/// These pin that the cross-map closes that gap, and that removing it changes
/// nothing else.
void main() {
  late Directory dir;
  late CacheDatabase db;
  late List<String> skipRequests;
  var seriesIdMal = <String, int?>{};

  Future<void> touch(String name) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    await f.writeAsString('xxxxx');
  }

  http.Response page(int id, String romaji, int? idMal) => http.Response(
    jsonEncode({
      'data': {
        'Page': {
          'media': [
            {
              'id': id,
              'idMal': idMal,
              'title': {'romaji': romaji, 'english': null, 'native': null},
              'format': 'TV',
              'episodes': 12,
              'coverImage': {'extraLarge': 'http://a/$id.jpg'},
              'relations': {'edges': []},
            },
          ],
        },
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// AniSkip answers for ANY mal id, and records what it was asked for — the
  /// assertion is about which id we looked up, not what came back.
  MockClient aniSkipMock() => MockClient((req) async {
    skipRequests.add(req.url.path);
    return http.Response(
      jsonEncode({
        'found': true,
        'results': [
          {
            'skipType': 'op',
            'interval': {'startTime': 0.0, 'endTime': 90.0},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  MockClient crossMapMock() => MockClient(
    (_) async => http.Response(
      jsonEncode([
        {'anilist_id': 500, 'mal_id': 60285, 'kitsu_id': 111},
      ]),
      200,
    ),
  );

  LibrarySync buildSync({required bool withCrossMap}) {
    final anilist = MockClient((req) async {
      if (req.method == 'POST') {
        final q = (jsonDecode(req.body)['variables']['search'] as String)
            .toLowerCase();
        if (q.contains('sakamoto')) {
          return page(500, 'Sakamoto Days', seriesIdMal['sakamoto']);
        }
        return http.Response(
          jsonEncode({
            'data': {
              'Page': {'media': []},
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    return LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(
        providers: [
          AniListMetadataProvider(AniListClient(httpClient: anilist)),
        ],
      ),
      cache: db,
      art: ArtCache(
        httpClient: anilist,
        directory: () async => Directory('${dir.path}/.art')..createSync(),
      ),
      aniSkip: AniSkipClient(httpClient: aniSkipMock()),
      crossMap: withCrossMap
          ? CrossMapStore(
              httpClient: crossMapMock(),
              directory: () async => dir,
            )
          : null,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_idmal_');
    db = CacheDatabase(NativeDatabase.memory());
    skipRequests = [];
    seriesIdMal = {'sakamoto': null}; // AniList knows the show, not its MAL id
    await touch('Sakamoto Days - 01.mkv');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'without the cross-map, a null idMal means no skip is ever fetched',
    () async {
      await buildSync(withCrossMap: false).sync([dir.path]);

      expect(skipRequests, isEmpty, reason: 'no MAL id -> nothing to ask for');
      expect(await db.allSkipRows(), isEmpty);
    },
  );

  test('the cross-map supplies the MAL id AniList omitted', () async {
    await buildSync(withCrossMap: true).sync([dir.path]);

    expect(
      skipRequests.single,
      contains('/60285/'),
      reason: 'AniSkip must be asked using the id the cross-map supplied',
    );
    final rows = await db.allSkipRows();
    expect(rows.single.seriesId, 500);
    expect(rows.single.introEndMs, 90000);
  });

  test('AniList\'s own idMal still wins when it has one', () async {
    seriesIdMal = {'sakamoto': 12345};

    await buildSync(withCrossMap: true).sync([dir.path]);

    expect(
      skipRequests.single,
      contains('/12345/'),
      reason: 'the provider is authoritative; the map only fills gaps',
    );
  });

  test('refreshMetadata backfills skips offline from the CACHE alone', () async {
    // The cross-map isn't the only fix here. A library populated while AniList
    // was healthy already stores idMal; before this change refreshMetadata
    // seeded its lookup ONLY from the live fetch, so an offline refresh found
    // nothing and backfilled no skips even for shows whose MAL id was known.
    seriesIdMal = {'sakamoto': 12345};
    await buildSync(withCrossMap: false).sync([dir.path]);
    await db.customStatement('DELETE FROM skip_segments');
    skipRequests.clear();

    final offline = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient(
                (_) async => throw const SocketException('offline'),
              ),
            ),
          ),
        ],
      ),
      cache: db,
      art: ArtCache(
        httpClient: MockClient((_) async => http.Response('', 500)),
        directory: () async => Directory('${dir.path}/.art')..createSync(),
      ),
      aniSkip: AniSkipClient(httpClient: aniSkipMock()),
      // No cross-map at all — the cached idMal must carry this on its own.
    );

    final result = await offline.refreshMetadata();

    expect(result.apiUnreachable, isTrue);
    expect(result.skipsFetched, 1);
    expect(skipRequests.single, contains('/12345/'));
  });

  test('refreshMetadata backfills skips offline, from cache + map', () async {
    // Populate while AniList is healthy but idMal-less, and with no skip data.
    await buildSync(withCrossMap: false).sync([dir.path]);
    expect(await db.allSkipRows(), isEmpty);
    skipRequests.clear();

    // Now AniList is entirely unreachable. The refresh must STILL resolve a MAL
    // id (cache + cross-map) and backfill the skip — the whole point of A1.
    final offline = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient(
                (_) async => throw const SocketException('offline'),
              ),
            ),
          ),
        ],
      ),
      cache: db,
      art: ArtCache(
        httpClient: MockClient((_) async => http.Response('', 500)),
        directory: () async => Directory('${dir.path}/.art')..createSync(),
      ),
      aniSkip: AniSkipClient(httpClient: aniSkipMock()),
      crossMap: CrossMapStore(
        httpClient: crossMapMock(),
        directory: () async => dir,
      ),
    );

    final result = await offline.refreshMetadata();

    expect(result.apiUnreachable, isTrue, reason: 'AniList really is down');
    expect(result.skipsFetched, 1);
    expect(skipRequests.single, contains('/60285/'));
  });
}
