import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `refreshMetadata` is the "backfill without a wipe" path. These tests pin
/// two things: that an unreachable AniList is REPORTED rather than swallowed
/// into a "Refreshed 0 series" success (it was a real bug), and that a
/// degraded response cannot blank fields on an existing library (already true,
/// but only by way of an implicit drift behaviour worth locking down).
void main() {
  late Directory dir;
  late Directory artDir;
  late CacheDatabase db;
  late LibrarySync sync;

  // Mock behaviour switches, flipped per test after a healthy seed scan.
  var anilistDown = false;
  var artDown = false;
  Map<String, dynamic>? refreshPayload; // null = the full, healthy payload.

  http.Response page(List<Map<String, dynamic>> media) => http.Response(
    jsonEncode({
      'data': {
        'Page': {'media': media},
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> full(int id, String romaji) => {
    'id': id,
    'idMal': 100 + id,
    'title': {'romaji': romaji, 'english': null, 'native': null},
    'format': 'TV',
    'episodes': 26,
    'coverImage': {'extraLarge': 'http://a/$id.jpg'},
    'relations': {'edges': []},
  };

  /// AniList's verbatim outage response: a 403 carrying a GraphQL envelope.
  http.Response apiDisabled() => http.Response(
    jsonEncode({
      'errors': [
        {
          'message':
              'The AniList API has been temporarily disabled due to '
              'severe stability issues.',
          'status': 403,
        },
      ],
      'data': null,
    }),
    403,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_refresh_');
    artDir = await Directory('${dir.path}/.art').create();
    db = CacheDatabase(NativeDatabase.memory());
    anilistDown = false;
    artDown = false;
    refreshPayload = null;

    final mock = MockClient((req) async {
      if (req.method == 'POST') {
        if (anilistDown) return apiDisabled();
        final vars = jsonDecode(req.body)['variables'] as Map<String, dynamic>;
        // Refresh fetches BY id; the scan searches by title.
        if (vars.containsKey('ids')) {
          return page([refreshPayload ?? full(1, 'Cowboy Bebop')]);
        }
        final q = (vars['search'] as String).toLowerCase();
        if (q.contains('cowboy')) return page([full(1, 'Cowboy Bebop')]);
        return page(const []);
      }
      // Art download.
      if (artDown) return http.Response('', 500);
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

    // Seed a healthy, populated library.
    final f = File('${dir.path}/Cowboy Bebop - 01.mkv');
    await f.create(recursive: true);
    await f.writeAsString('xxxxx');
    await sync.sync([dir.path]);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<CachedSeriesRow> seriesRow() async =>
      (await db.allSeriesRows()).firstWhere((r) => r.anilistId == 1);

  test(
    'an unreachable AniList is reported, not a "refreshed 0" success',
    () async {
      final before = await seriesRow();
      anilistDown = true;

      final result = await sync.refreshMetadata();

      // The bug this pins: the exception was swallowed, so the UI took the
      // success branch and told the user "Refreshed 0 series" during an outage.
      expect(result.failure, MetadataFailure.service);
      expect(result.apiUnreachable, isTrue);
      expect(result.seriesRefreshed, 0);
      expect(
        await seriesRow(),
        before,
        reason: 'a failed refresh must leave the cache byte-identical',
      );
    },
  );

  test('an offline refresh is attributed to the connection', () async {
    sync = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(
        anilist: AniListClient(
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      ),
      cache: db,
      art: ArtCache(
        httpClient: MockClient((_) async => http.Response('', 500)),
        directory: () async => artDir,
      ),
      aniSkip: AniSkipClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      ),
    );

    final result = await sync.refreshMetadata();

    expect(result.failure, MetadataFailure.connection);
  });

  test('a healthy refresh reports no failure', () async {
    final result = await sync.refreshMetadata();

    expect(result.failure, isNull);
    expect(result.seriesRefreshed, 1);
  });

  test('a degraded payload cannot blank fields on an existing library', () async {
    final before = await seriesRow();
    expect(before.romaji, 'Cowboy Bebop');
    expect(before.episodeCount, 26);

    // AniList answers 200 but with a stripped-down entry — every optional
    // field absent. The row written is wholesale, so the protection comes from
    // drift: insertOnConflictUpdate's DO UPDATE SET omits null columns
    // (toColumns(nullToAbsent: true)), leaving cached values in place. That is
    // implicit and easy to lose in a refactor to explicit companions, which is
    // exactly why it is pinned here.
    refreshPayload = {
      'id': 1,
      'idMal': null,
      'title': {'romaji': null, 'english': null, 'native': null},
      'format': null,
      'episodes': null,
      'coverImage': {'extraLarge': null},
      'relations': {'edges': []},
    };

    final result = await sync.refreshMetadata();

    expect(result.failure, isNull);
    final after = await seriesRow();
    expect(after.romaji, 'Cowboy Bebop', reason: 'title preserved');
    expect(after.episodeCount, 26, reason: 'episode count preserved');
    expect(after.idMal, before.idMal, reason: 'idMal preserved');
  });

  test('a failed art download keeps the cover we already had', () async {
    final before = await seriesRow();
    expect(before.coverImagePath, isNotNull);

    // The cached art file is gone from disk (so ensureCover re-downloads) and
    // the download fails, returning null. Same drift null-omission guarantee:
    // the stored cover path must survive rather than be overwritten with null.
    await File(before.coverImagePath!).delete();
    artDown = true;

    await sync.refreshMetadata();

    expect((await seriesRow()).coverImagePath, before.coverImagePath);
  });
}
