import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/skip_view_source.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/data/skip/aniskip_skip_provider.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_art.dart';
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

Map<String, dynamic> _m(int id, String romaji) => {
  'id': id,
  'title': {'romaji': romaji, 'english': null, 'native': null},
  'format': 'TV',
  'episodes': 26,
  'coverImage': {'extraLarge': 'http://a/$id.jpg', 'large': 'http://a/$id.jpg'},
};

/// Pin the copy that lives in [folder] — the per-FILE pin, chosen the way the
/// UI does: from the episode's own source list.
Future<void> _pinFolder(
  DriftLibraryRepository repo,
  Episode e,
  String folder,
) => repo.selectSource(e, e.sources.firstWhere((s) => s.folderPath == folder));

void main() {
  group('multi-source episodes', () {
    late Directory root;
    late Directory folderA; // inserted first  -> sortOrder 0 -> higher priority
    late Directory folderB; // inserted second -> sortOrder 1 -> lower priority
    late CacheDatabase db;
    late LibrarySync sync;
    late DriftLibraryRepository repo;

    // Same episode file (Cowboy Bebop ep 3) dropped into a given folder.
    Future<File> dropEp3(Directory folder, {int size = 800}) async {
      final f = File('${folder.path}/Cowboy Bebop - 03.mkv');
      await f.create(recursive: true);
      await f.writeAsString('x' * size);
      return f;
    }

    Future<Episode> ep3() async =>
        (await repo.episodesFor(1)).firstWhere((e) => e.number == 3);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('anilocal_multisrc_');
      folderA = await Directory('${root.path}/A').create();
      folderB = await Directory('${root.path}/B').create();
      db = CacheDatabase(NativeDatabase.memory());
      final artDir = await Directory('${root.path}/.art').create();
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          final q = (graphqlVariables(req)['search'] as String).toLowerCase();
          return _page(
            q.contains('cowboy') ? [_m(1, 'Cowboy Bebop')] : const [],
          );
        }
        return http.Response.bytes(kFakeJpeg, 200);
      });
      sync = LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          providers: [AniListMetadataProvider(AniListClient(httpClient: mock))],
        ),
        cache: db,
        art: ArtCache(httpClient: mock, directory: () async => artDir),
        skipProviders: [
          AniSkipSkipProvider(
            AniSkipClient(
              httpClient: MockClient((_) async => http.Response('', 404)),
            ),
          ),
        ],
      );
      repo = DriftLibraryRepository(
        db,
        skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      );
      // Priority order is established by insert order (Stage 5 sortOrder).
      await db.insertFolder(folderA.path);
      await db.insertFolder(folderB.path);
    });

    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    test(
      'one episode in two folders shows as a SINGLE row with two sources',
      () async {
        await dropEp3(folderA);
        await dropEp3(folderB);
        await sync.sync([folderA.path, folderB.path]);

        final episodes = await repo.episodesFor(1);
        expect(
          episodes.length,
          1,
          reason: 'de-duplicated to one logical episode',
        );
        expect(episodes.single.hasMultipleSources, isTrue);
        expect(episodes.single.sources.length, 2);
      },
    );

    test('the ONE-read episodesBySeries agrees with N per-series reads', () async {
      // The grid used to call `episodesFor` once per card, and each call
      // rebuilt the whole library from five tables. The batch read must return
      // exactly what those calls would have — same episodes, same sources, same
      // resolution — for every series.
      await sync.sync([folderA.path, folderB.path]);
      final all = await repo.episodesBySeries();
      final series = await repo.allSeries();
      expect(all.keys.toSet(), {for (final s in series) s.seriesId});
      for (final s in series) {
        expect(all[s.seriesId], await repo.episodesFor(s.seriesId));
      }
    });

    test('Automatic skips a copy whose folder is not mounted', () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);
      expect((await ep3()).fileRef, contains('/A/'), reason: 'priority first');

      // The drive holding A is pulled: its stored path no longer exists and
      // it is bound to no volume, so it resolves to nothing. The default used
      // to stay on it and every play failed until the user pinned B by hand.
      await folderA.delete(recursive: true);
      final e = await ep3();
      expect(e.fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
      expect(e.sources, hasLength(2), reason: 'the copy is still listed');
      expect(e.pinnedSourceFolder, isNull, reason: 'still Automatic');
    });

    test('Automatic skips a 0-byte copy', () async {
      await dropEp3(folderA, size: 0); // a download that never happened
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);
      expect((await ep3()).fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
    });

    test('two copies in ONE folder are two pins, not one', () async {
      await dropEp3(folderA);
      final second = File(
        '${folderA.path}/[Group] Cowboy Bebop - 03 [1080p].mkv',
      );
      await second.writeAsString('y' * 900);
      await sync.sync([folderA.path, folderB.path]);
      final e = await ep3();
      final inA = e.sources.where((s) => s.folderPath == folderA.path).toList();
      expect(inA, hasLength(2));
      expect(inA.map((s) => s.relativePath).toSet(), {
        'Cowboy Bebop - 03.mkv',
        '[Group] Cowboy Bebop - 03 [1080p].mkv',
      });

      // Pin the SECOND one: it plays, and only it reads as pinned. A folder
      // pin used to play the alphabetically-first file whichever was tapped
      // and mark both as chosen.
      final chosen = inA.firstWhere((s) => s.fileRef == second.path);
      await repo.selectSource(e, chosen);
      final pinned = await ep3();
      expect(pinned.fileRef, second.path);
      expect(pinned.isPinned(chosen), isTrue);
      expect(
        pinned.sources.where(pinned.isPinned).toList(),
        hasLength(1),
        reason: 'exactly one copy reads as pinned',
      );
    });

    test(
      'a legacy folder pin (no file) still resolves to that folder',
      () async {
        await dropEp3(folderA);
        await dropEp3(folderB);
        await sync.sync([folderA.path, folderB.path]);
        // What a v21 cache holds after the v22 migration: relative_path null.
        await db.upsertSourceOverride(
          SourceOverrideRow(
            seriesId: 1,
            episode: 3,
            folderPath: folderB.path,
            updatedAtMs: 1,
          ),
        );
        final e = await ep3();
        expect(e.fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
        expect(e.pinnedSourceFolder, folderB.path);
        // Resolved to the copy it selected, so exactly one copy reads as
        // pinned (two same-folder copies both read as chosen before).
        expect(e.pinnedSourceRelativePath, 'Cowboy Bebop - 03.mkv');
        expect(e.sources.where(e.isPinned).toList(), hasLength(1));
      },
    );

    test('default source is the highest-priority folder that has it', () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);

      // folderA was inserted first (sortOrder 0) -> preferred.
      expect((await ep3()).fileRef, '${folderA.path}/Cowboy Bebop - 03.mkv');
    });

    test('falls down the priority order when #1 lacks the episode', () async {
      await dropEp3(folderB); // only the lower-priority folder has it
      await sync.sync([folderA.path, folderB.path]);

      final e = await ep3();
      expect(e.hasMultipleSources, isFalse);
      expect(e.fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
    });

    test('manual source override beats priority AND survives a rescan', () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);
      expect((await ep3()).fileRef, contains('/A/')); // priority default

      await _pinFolder(repo, await ep3(), folderB.path);
      expect((await ep3()).fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');

      // A rescan must never clobber the manual choice (seam #5, source dimension).
      await sync.sync([folderA.path, folderB.path]);
      expect((await ep3()).fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
    });

    test(
      'override on #2 holds even after the higher-priority folder gains it',
      () async {
        // Start with the episode ONLY in the lower-priority folder, pin it there.
        await dropEp3(folderB);
        await sync.sync([folderA.path, folderB.path]);
        await _pinFolder(repo, await ep3(), folderB.path);

        // Later, folder #1 gains the same episode. Without an override the default
        // would flip to #1 — but the pin to #2 wins.
        await dropEp3(folderA);
        await sync.sync([folderA.path, folderB.path]);

        final e = await ep3();
        expect(
          e.hasMultipleSources,
          isTrue,
          reason: 'both folders now have it',
        );
        expect(e.fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
      },
    );

    test('clearing the override reverts to the priority default', () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);
      await _pinFolder(repo, await ep3(), folderB.path);
      expect((await ep3()).fileRef, contains('/B/'));

      await repo.clearSource(await ep3());
      expect((await ep3()).fileRef, contains('/A/'));
    });

    test(
      'watch progress is shared across sources (per logical episode)',
      () async {
        await dropEp3(folderA);
        await dropEp3(folderB);
        await sync.sync([folderA.path, folderB.path]);

        // Watch from the default source (folder A).
        await repo.saveProgress(
          await ep3(),
          position: const Duration(minutes: 12),
          duration: const Duration(minutes: 24),
        );

        // Switch the source to folder B — same logical episode, same progress.
        await _pinFolder(repo, await ep3(), folderB.path);
        final e = await ep3();
        expect(e.fileRef, contains('/B/'), reason: 'now playing the B copy');
        expect(
          e.resumePosition,
          const Duration(minutes: 12),
          reason: 'progress keyed by identity, not by source file',
        );
      },
    );

    test('switching source never touches files on disk', () async {
      final a = await dropEp3(folderA);
      final b = await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);

      await _pinFolder(repo, await ep3(), folderB.path);
      await repo.clearSource(await ep3());

      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);
    });

    test('a removed override-target folder falls back to priority', () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);
      await _pinFolder(repo, await ep3(), folderB.path);
      expect((await ep3()).fileRef, contains('/B/'));

      // Folder B is removed (its files drop out of the cache). The inert override
      // row remains but resolution falls back to the only surviving source.
      await db.removeFolderAndFiles(folderB.path);
      final e = await ep3();
      expect(e.hasMultipleSources, isFalse);
      expect(e.fileRef, '${folderA.path}/Cowboy Bebop - 03.mkv');
    });
  });
}
