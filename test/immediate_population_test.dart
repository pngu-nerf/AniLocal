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

/// Immediate library population + the pending -> identified lifecycle.
///
/// The model: a file enters the library the moment it's scanned, as a NAMED
/// placeholder (parsed title, no art), even before/without AniList. Identifying
/// is a background upgrade — the same record gains real metadata when AniList
/// resolves; it is never re-added. A pending file is distinct from a
/// confirmed-unmatched file and resolves on its own once online.
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
  var emptyResults = false; // AniList reachable but genuinely no match

  Future<void> touch(String name, int size) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    await f.writeAsString('x' * size);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_pending_');
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    anilistDown = false;
    emptyResults = false;
    final artDir = await Directory('${dir.path}/.art').create();
    final mock = MockClient((req) async {
      if (req.method == 'POST') {
        if (anilistDown) return http.Response('forbidden', 403);
        if (emptyResults) return _page(const []);
        final q = (jsonDecode(req.body)['variables']['search'] as String)
            .toLowerCase();
        if (q.contains('cowboy')) return _page([_m(1, 'Cowboy Bebop')]);
        return _page(const []);
      }
      return http.Response.bytes([1, 2, 3], 200); // art bytes
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

  test('offline scan shows anime immediately as named placeholders', () async {
    await touch('Cowboy Bebop - 01.mkv', 100);
    await touch('Cowboy Bebop - 02.mkv', 200);
    anilistDown = true;

    final s = await sync.sync([dir.path]);

    // The whole library reflects what's on disk despite AniList being down.
    expect(s.apiUnreachable, isTrue);
    final series = await repo.allSeries();
    final placeholder = series.single;
    expect(placeholder.pending, isTrue);
    expect(placeholder.titles.romaji, 'Cowboy Bebop'); // the parsed name
    expect(placeholder.coverImageRef, isNull); // blank art

    // Its files are present (and playable) under the placeholder.
    final eps = await repo.episodesFor(placeholder.anilistId);
    expect(eps.map((e) => e.number), [1, 2]);

    // A placeholder is NOT a confirmed-unmatched file — it stays out of the
    // fix-match screen ("not yet tried", not "couldn't identify").
    expect(await repo.unmatchedFiles(), isEmpty);
  });

  test(
    'placeholders are written (and surfaced) before identification',
    () async {
      await touch('Cowboy Bebop - 01.mkv', 100);

      var step = 0;
      int? discoveredAt;
      int? lookupAt;

      final ordered = LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          anilist: AniListClient(
            httpClient: MockClient((req) async {
              if (req.method == 'POST') {
                lookupAt ??= step++;
                return _page([_m(1, 'Cowboy Bebop')]);
              }
              return http.Response.bytes([1, 2, 3], 200);
            }),
          ),
        ),
        cache: db,
        art: ArtCache(
          httpClient: MockClient((_) async => http.Response.bytes([1], 200)),
          directory: () async =>
              Directory('${dir.path}/.art2')..createSync(recursive: true),
        ),
        aniSkip: AniSkipClient(
          httpClient: MockClient((_) async => http.Response('', 404)),
        ),
      );

      // Capture the cache state at the moment discovery fires (phase 1 done,
      // before the network lookup) and await it after the run.
      Future<List<CachedFileRow>>? rowsAtDiscovery;
      await ordered.sync(
        [dir.path],
        onDiscovered: () {
          discoveredAt = step++;
          rowsAtDiscovery = db.allFileRows();
        },
      );

      expect(discoveredAt, isNotNull, reason: 'onDiscovered fired');
      expect(lookupAt, isNotNull, reason: 'identification ran');
      expect(
        discoveredAt! < lookupAt!,
        isTrue,
        reason: 'discovery/placeholder write happens before the AniList lookup',
      );
      // The pending placeholder row already existed when discovery fired.
      final atDiscovery = await rowsAtDiscovery!;
      expect(
        atDiscovery.any((r) => r.pendingIdentification && r.anilistId == null),
        isTrue,
      );

      // After the lookup the placeholder upgraded in place to the real match.
      final series = await repo.allSeries();
      expect(series.single.pending, isFalse);
      expect(series.single.anilistId, 1);
    },
  );

  test('placeholder upgrades in place once AniList resolves', () async {
    await touch('Cowboy Bebop - 01.mkv', 100);

    // First scan offline -> a pending placeholder.
    anilistDown = true;
    await sync.sync([dir.path]);
    expect((await repo.allSeries()).single.pending, isTrue);

    // Back online, rescan (the file is UNCHANGED on disk, yet a pending row is
    // always retried) -> upgraded in place: same library entry, now matched.
    anilistDown = false;
    final s = await sync.sync([dir.path]);

    expect(s.matched, 1, reason: 'pending file re-attempted and resolved');
    final series = await repo.allSeries();
    expect(series.single.pending, isFalse);
    expect(series.single.anilistId, 1);
    expect(series.single.titles.romaji, 'Cowboy Bebop');
    expect(series.single.coverImageRef, isNotNull); // art now present
    expect(File(series.single.coverImageRef!).existsSync(), isTrue);
    expect(await repo.unmatchedFiles(), isEmpty);
  });

  test(
    'a genuine no-match is confirmed-unmatched, not a pending placeholder',
    () async {
      await touch('Some Obscure Thing - 01.mkv', 100);
      emptyResults = true; // AniList reachable, returns nothing

      await sync.sync([dir.path]);

      // It lands in the fix-match screen, NOT the library grid.
      final unmatched = await repo.unmatchedFiles();
      expect(unmatched.single.parsedTitle, 'Some Obscure Thing');
      expect(await repo.allSeries(), isEmpty);

      // And it is NOT retried on a later scan (it's resolved, just unmatched) —
      // unlike a pending file. Unchanged on disk -> counted unchanged, 0 looks.
      final s2 = await sync.sync([dir.path]);
      expect(s2.unchanged, 1);
      expect(s2.anilistLookups, 0);
    },
  );

  test(
    'watch progress on a placeholder carries over to the real id on identify',
    () async {
      await touch('Cowboy Bebop - 01.mkv', 100);

      // Pending placeholder (offline), then watch it and accumulate a resume.
      anilistDown = true;
      await sync.sync([dir.path]);
      final placeholder = (await repo.allSeries()).single;
      expect(placeholder.pending, isTrue);
      final synthId = placeholder.anilistId;
      expect(synthId, isNegative, reason: 'synthetic placeholder id');

      final pendingEp = (await repo.episodesFor(synthId)).single;
      await repo.saveProgress(
        pendingEp,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );
      // The progress is (transiently) keyed by the synthetic id for now.
      expect(
        (await db.watchStateFor(
          synthId,
          pendingEp.anchoredNumber,
        ))!.resumePositionMs,
        5000,
      );

      // Back online, rescan -> the file identifies (real id 1).
      anilistDown = false;
      await sync.sync([dir.path]);
      final matched = (await repo.allSeries()).single;
      expect(matched.pending, isFalse);
      expect(matched.anilistId, 1);

      // Resume carried over to the REAL series — not stranded.
      final realEp = (await repo.episodesFor(1)).single;
      expect(realEp.resumePosition, const Duration(seconds: 5));
      // ...and it surfaces in Continue Watching under the real series.
      final cont = await repo.continueWatching();
      expect(cont.single.series.anilistId, 1);
      expect(cont.single.episode.resumePosition, const Duration(seconds: 5));

      // The synthetic id is GONE from durable storage — nothing keyed to it.
      expect(await db.watchStateFor(synthId, pendingEp.anchoredNumber), isNull);
      final rows = await db.allWatchStateRows();
      expect(rows.every((r) => r.anilistId >= 0), isTrue);
      expect(rows.single.anilistId, 1);
    },
  );
}
