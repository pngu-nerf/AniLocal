import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_connection.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/series_identity.dart';
import 'package:anilocal/data/cache/skip_view_source.dart';
import 'package:anilocal/data/json_http.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/data/source_exception.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/episode_source.dart';
import 'package:anilocal/domain/models/folder_refused.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:anilocal/sync/source_health.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_art.dart';
import 'support/fake_metadata_provider.dart';
import 'support/fake_skip_provider.dart';
import 'support/graphql_request.dart';

http.Response _page(List<Map<String, dynamic>> media) => http.Response(
  jsonEncode({
    'data': {
      'Page': {'media': media},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _bebop() => {
  'id': 1,
  'idMal': 1,
  'title': {'romaji': 'Cowboy Bebop', 'english': null, 'native': null},
  'format': 'TV',
  'episodes': 26,
  'coverImage': {'extraLarge': 'https://art.test/1.jpg'},
};

/// AniList answers "Cowboy Bebop" for anything containing "cowboy"; art is a
/// valid JPEG header.
MockClient _anilist() => MockClient((req) async {
  if (req.method == 'POST') {
    final search = (graphqlVariables(req)['search']) as String;
    return search.toLowerCase().contains('cowboy')
        ? _page([_bebop()])
        : _page(const []);
  }
  return http.Response.bytes(kFakeJpeg, 200);
});

/// A folder whose drive is pulled DURING the walk: the listing that comes
/// back is partial (here: empty), and the root is gone by the time it does.
class _VanishingScanner extends FolderScanner {
  const _VanishingScanner();

  @override
  Future<List<String>> findVideoFiles(String folderPath) async => const [];

  @override
  Future<Map<String, FileSig>> statVideoFiles(String folderPath) async {
    await Directory(folderPath).delete(recursive: true);
    return const {};
  }
}

class _TestException extends SourceException {
  const _TestException(super.message, {super.failure});
}

/// What happens at the boundaries the audit traced: a touched file, a
/// placeholder played mid-identification, a blackholed network, a drive
/// pulled mid-walk, nested folders, symlinks, non-image art, a refused TLS
/// handshake, and a cache that has to be set aside.
void main() {
  late Directory dir;
  late CacheDatabase db;

  Future<File> touch(String rel, {String content = 'x'}) async {
    final f = File('${dir.path}/$rel');
    await f.create(recursive: true);
    await f.writeAsString(content);
    return f;
  }

  LibrarySync syncWith({
    FolderScanner scanner = const FileSystemFolderScanner(),
    List<SkipProvider> skipProviders = const [],
  }) {
    final mock = _anilist();
    return LibrarySync(
      scanner: scanner,
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(
        providers: [AniListMetadataProvider(AniListClient(httpClient: mock))],
      ),
      cache: db,
      art: ArtCache(
        httpClient: mock,
        directory: () async =>
            Directory('${dir.path}/.art')..createSync(recursive: true),
      ),
      skipProviders: skipProviders,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_bounds_');
    db = CacheDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('overrides follow the file', () {
    test('a fix-match survives the file being touched', () async {
      final file = await touch('lib/Cowboy Bebop - 01.mkv');
      final folder = '${dir.path}/lib';
      await syncWith().sync([folder]);
      // The user's correction, keyed by the CURRENT fingerprint (as fix-match
      // writes it): this file is really episode 5.
      final stat = await file.stat();
      await db.upsertOverride(
        MatchOverrideRow(
          fileSize: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          seriesId: 1,
          anchoredEpisode: 5,
          continuousOffset: 0,
          displayContinuous: false,
        ),
      );

      // Re-download / mkvpropedit / backup restore: same path, new bytes.
      await file.writeAsString('a longer body than before');
      final after = await file.stat();
      expect(after.size, isNot(stat.size));
      await syncWith().sync([folder]);

      final overrides = await db.allOverrideRows();
      expect(overrides, hasLength(1), reason: 'moved, not dropped');
      expect(overrides.single.fileSize, after.size);
      expect(overrides.single.anchoredEpisode, 5);
      // And it took effect where episodes are built: the read path applies
      // the override by fingerprint, so the show still lists episode 5.
      final repo = DriftLibraryRepository(
        db,
        skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      );
      final episodes = await repo.episodesFor(1);
      expect(episodes.single.anchoredNumber, 5);
    });

    test(
      'rekeyOverrides moves a row and leaves an occupied target alone',
      () async {
        await db.upsertSeries(const CachedSeriesRow(seriesId: 1));
        await db.upsertOverride(
          const MatchOverrideRow(
            fileSize: 10,
            modifiedAtMs: 100,
            seriesId: 1,
            anchoredEpisode: 3,
            continuousOffset: 0,
            displayContinuous: false,
          ),
        );
        await db.upsertOverride(
          const MatchOverrideRow(
            fileSize: 30,
            modifiedAtMs: 300,
            seriesId: 1,
            anchoredEpisode: 9,
            continuousOffset: 0,
            displayContinuous: false,
          ),
        );
        await db.rekeyOverrides([
          ((size: 10, modifiedMs: 100), (size: 20, modifiedMs: 200)),
          // Target already carries its own override: OR IGNORE keeps it.
          ((size: 20, modifiedMs: 999), (size: 30, modifiedMs: 300)),
        ]);
        final rows = await db.allOverrideRows();
        final byKey = {for (final r in rows) (r.fileSize, r.modifiedAtMs): r};
        expect(byKey[(20, 200)]?.anchoredEpisode, 3);
        expect(byKey[(30, 300)]?.anchoredEpisode, 9);
        expect(byKey.containsKey((10, 100)), isFalse);
      },
    );
  });

  group('progress writes resolve identity at write time', () {
    test('a placeholder played mid-scan lands on the real series', () async {
      await touch('lib/Cowboy Bebop - 01.mkv');
      final folder = '${dir.path}/lib';
      await syncWith().sync([folder]);
      final repo = DriftLibraryRepository(
        db,
        skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      );
      // The session still holds the id it opened with — the placeholder's.
      final stale = Episode(
        number: 1,
        anchoredNumber: 1,
        seriesId: placeholderSeriesId('cowboy bebop'),
        fileRef: '$folder/Cowboy Bebop - 01.mkv',
        sources: [
          EpisodeSource(
            fileRef: '$folder/Cowboy Bebop - 01.mkv',
            folderPath: folder,
            folderSortOrder: 0,
          ),
        ],
      );
      expect(isPlaceholderSeriesId(stale.seriesId), isTrue);
      await repo.saveProgress(
        stale,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 24),
      );
      final rows = await db.allWatchStateRows();
      expect(rows.single.seriesId, 1, reason: 'resolved by file, not by id');
      expect(rows.single.resumePositionMs, 5 * 60 * 1000);
    });

    test('a file still pending keeps its placeholder id', () async {
      // Nothing identified this file; there is nothing to resolve to.
      final stale = Episode(
        number: 1,
        anchoredNumber: 1,
        seriesId: placeholderSeriesId('unknown'),
        fileRef: '/nowhere/Unknown - 01.mkv',
        sources: const [
          EpisodeSource(
            fileRef: '/nowhere/Unknown - 01.mkv',
            folderPath: '/nowhere',
            folderSortOrder: 0,
          ),
        ],
      );
      final repo = DriftLibraryRepository(
        db,
        skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      );
      await repo.saveProgress(
        stale,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 24),
      );
      expect((await db.allWatchStateRows()).single.seriesId, stale.seriesId);
    });
  });

  group('the per-run circuit breaker', () {
    test('two transport failures mark a source down; anything else resets', () {
      final h = SourceHealth();
      h.failed('a', MetadataFailure.connection);
      expect(h.isDown('a'), isFalse, reason: 'one is a blip');
      h.failed('a', MetadataFailure.blocked);
      expect(h.isDown('a'), isTrue);
      expect(h.down, ['a']);

      h.failed('b', MetadataFailure.connection);
      h.succeeded('b');
      h.failed('b', MetadataFailure.connection);
      expect(h.isDown('b'), isFalse, reason: 'a success resets the count');

      h.failed('c', MetadataFailure.connection);
      h.failed('c', MetadataFailure.service);
      h.failed('c', MetadataFailure.connection);
      expect(h.isDown('c'), isFalse, reason: 'a 5xx is an ANSWER, not silence');
    });

    test('the matcher stops asking a source that is down', () async {
      final dead = FakeMetadataProvider(
        'dead',
        failure: MetadataFailure.connection,
      );
      final alive = FakeMetadataProvider('alive', answersTitle: true);
      final matcher = SeriesMatcher(providers: [dead, alive]);
      final health = SourceHealth();
      for (final title in ['One', 'Two', 'Three', 'Four']) {
        final r = await matcher.match(
          title,
          providers: [dead, alive],
          health: health,
        );
        expect(r.source, 'alive');
      }
      expect(dead.searchCalls, 2, reason: 'asked until down, then never');
      expect(alive.searchCalls, 4);
      expect(health.down, ['dead']);
    });

    test(
      'a skip source that cannot be reached is asked twice, not per episode',
      () async {
        for (final n in ['01', '02', '03', '04']) {
          await touch('lib/Cowboy Bebop - $n.mkv');
        }
        final dead = FakeSkipProvider(
          'dead',
          failure: MetadataFailure.connection,
        );
        final summary = await syncWith(
          skipProviders: [dead],
        ).sync(['${dir.path}/lib']);
        expect(summary.matched, 4);
        expect(dead.calls, 2);
        expect(summary.skipLookupsFailed, 2);
        expect(summary.sourcesDown, ['dead']);
        // Nothing recorded, so the next run asks again.
        expect(await db.allSkipAnswers(), isEmpty);
      },
    );
  });

  group('folders', () {
    test(
      'a nested folder\'s files are written once, under the nearest folder',
      () async {
        await touch('parent/child/Cowboy Bebop - 01.mkv');
        final parent = '${dir.path}/parent';
        final child = '$parent/child';
        final summary = await syncWith().sync([parent, child]);
        expect(summary.filesScanned, 1);
        final rows = await db.allFileRows();
        expect(rows, hasLength(1), reason: 'not one copy per enclosing folder');
        expect(rows.single.folderPath, child);
        expect(rows.single.relativePath, 'Cowboy Bebop - 01.mkv');
      },
    );

    test(
      'a drive pulled mid-walk marks the folder unreadable and keeps its files',
      () async {
        await touch('lib/Cowboy Bebop - 01.mkv');
        final folder = '${dir.path}/lib';
        await syncWith().sync([folder]);
        expect(await db.allFileRows(), hasLength(1));

        final summary = await syncWith(
          scanner: const _VanishingScanner(),
        ).sync([folder]);
        expect(summary.unreadableFolders, [folder]);
        expect(
          summary.removed,
          0,
          reason: 'a partial listing is not "removed"',
        );
        expect(await db.allFileRows(), hasLength(1));
        expect(await db.allSeriesRows(), hasLength(1));
      },
    );

    test(
      'a symlink to a file is included; a symlink to a folder is not followed',
      () async {
        final outside = await Directory('${dir.path}/outside').create();
        final real = File('${outside.path}/Cowboy Bebop - 01.mkv');
        await real.writeAsString('xx');
        await File('${outside.path}/Cowboy Bebop - 02.mkv').writeAsString('y');
        final lib = await Directory('${dir.path}/lib').create();
        await Link('${lib.path}/Bebop 01 (linked).mkv').create(real.path);
        await Link('${lib.path}/more').create(outside.path);

        final found = await const FileSystemFolderScanner().statVideoFiles(
          lib.path,
        );
        expect(found.keys, ['${lib.path}/Bebop 01 (linked).mkv']);
        expect(found.values.single.size, 2, reason: 'the TARGET is statted');
      },
    );

    test('adding a folder is refused when it is already there or nests', () {
      const existing = ['/Volumes/Anime/Shows', '/Users/me/Library/anime'];
      expect(folderRefusal('/Volumes/Anime/Shows/', existing), isNotNull);
      expect(
        folderRefusal('/Volumes/Anime/Shows/Bebop', existing)?.userMessage,
        contains('inside /Volumes/Anime/Shows'),
      );
      expect(
        folderRefusal('/Volumes/Anime', existing)?.userMessage,
        contains('contains /Volumes/Anime/Shows'),
      );
      expect(
        folderRefusal('/Volumes/Anime2', existing),
        isNull,
        reason: 'a shared prefix is not nesting',
      );
      expect(folderRefusal('/Volumes/Other', existing), isNull);
      expect(normalizeFolderPath('/a/b///'), '/a/b');
      expect(normalizeFolderPath('/'), '/');
    });
  });

  group('art is validated', () {
    ArtCache art(MockClient client) => ArtCache(
      httpClient: client,
      directory: () async => Directory('${dir.path}/art')..createSync(),
    );

    test('a 200 that is not an image is not written', () async {
      final a = art(
        MockClient((_) async => http.Response.bytes(kFakeHtml, 200)),
      );
      expect(await a.ensureCover(7, 'https://cdn.test/7.jpg'), isNull);
      expect(Directory('${dir.path}/art').listSync(), isEmpty);
    });

    test(
      'a cached file that is not an image is replaced, not reused',
      () async {
        final file = File('${dir.path}/art/7.jpg')..createSync(recursive: true);
        file.writeAsBytesSync(kFakeHtml);
        var calls = 0;
        final a = art(
          MockClient((_) async {
            calls++;
            return http.Response.bytes(kFakeJpeg, 200);
          }),
        );
        final path = await a.ensureCover(7, 'https://cdn.test/7.jpg');
        expect(calls, 1, reason: 'the poisoned file did not short-circuit');
        expect(File(path!).readAsBytesSync(), kFakeJpeg);
      },
    );

    test('deleteExcept collects an unfinished .part', () async {
      final d = Directory('${dir.path}/art')..createSync();
      File('${d.path}/7.jpg').writeAsBytesSync(kFakeJpeg);
      File('${d.path}/9.jpg.part').writeAsBytesSync([1]);
      final a = art(MockClient((_) async => http.Response('', 404)));
      await a.deleteExcept({7});
      expect(d.listSync().map((e) => e.uri.pathSegments.last).toList(), [
        '7.jpg',
      ]);
    });

    test('looksLikeImage knows the four formats and nothing else', () {
      expect(looksLikeImage(kFakeJpeg), isTrue);
      expect(
        looksLikeImage([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0,
          0,
          0,
          0,
        ]),
        isTrue,
      );
      expect(looksLikeImage('GIF89a......'.codeUnits), isTrue);
      expect(looksLikeImage('RIFF....WEBP'.codeUnits), isTrue);
      expect(looksLikeImage(kFakeHtml), isFalse);
      expect(looksLikeImage([0xFF, 0xD8]), isFalse, reason: 'too short');
    });
  });

  group('the network', () {
    test(
      'a refused TLS handshake is BLOCKED, not "check your internet"',
      () async {
        final json = JsonHttp(
          MockClient((_) async => throw const HandshakeException('refused')),
          service: 'Svc',
          fail: (m, {required failure}) => _TestException(m, failure: failure),
          sleep: (_) async {},
        );
        try {
          await json.getJson(Uri.parse('https://svc.test/x'));
          fail('expected a failure');
        } on _TestException catch (e) {
          expect(e.failure, MetadataFailure.blocked);
        }
        final plain = JsonHttp(
          MockClient((_) async => throw const SocketException('refused')),
          service: 'Svc',
          fail: (m, {required failure}) => _TestException(m, failure: failure),
          sleep: (_) async {},
        );
        try {
          await plain.getJson(Uri.parse('https://svc.test/x'));
          fail('expected a failure');
        } on _TestException catch (e) {
          expect(e.failure, MetadataFailure.connection);
        }
      },
    );
  });

  group('the cache reset', () {
    test('moves the database and its sidecars aside, never deletes', () async {
      final file = File('${dir.path}/cache.sqlite')..writeAsStringSync('db');
      File('${dir.path}/cache.sqlite-wal').writeAsStringSync('wal');
      final moved = await quarantineCacheFile(file);
      expect(moved, startsWith('${file.path}.broken-'));
      expect(file.existsSync(), isFalse);
      expect(File(moved).readAsStringSync(), 'db');
      expect(File('$moved-wal').readAsStringSync(), 'wal');
      expect(File('${file.path}-wal').existsSync(), isFalse);
    });
  });
}
