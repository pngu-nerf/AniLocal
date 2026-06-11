import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/episode.dart';
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
  'title': {'romaji': romaji, 'english': null, 'native': null},
  'format': 'TV',
  'episodes': 26,
  'coverImage': {'extraLarge': 'http://a/$id.jpg', 'large': 'http://a/$id.jpg'},
};

void main() {
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
        final q = (jsonDecode(req.body)['variables']['search'] as String)
            .toLowerCase();
        return _page(q.contains('cowboy') ? [_m(1, 'Cowboy Bebop')] : const []);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    sync = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(anilist: AniListClient(httpClient: mock)),
      cache: db,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
    );
    repo = DriftLibraryRepository(db);
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

    await repo.selectSource(await ep3(), folderPath: folderB.path);
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
      await repo.selectSource(await ep3(), folderPath: folderB.path);

      // Later, folder #1 gains the same episode. Without an override the default
      // would flip to #1 — but the pin to #2 wins.
      await dropEp3(folderA);
      await sync.sync([folderA.path, folderB.path]);

      final e = await ep3();
      expect(e.hasMultipleSources, isTrue, reason: 'both folders now have it');
      expect(e.fileRef, '${folderB.path}/Cowboy Bebop - 03.mkv');
    },
  );

  test('clearing the override reverts to the priority default', () async {
    await dropEp3(folderA);
    await dropEp3(folderB);
    await sync.sync([folderA.path, folderB.path]);
    await repo.selectSource(await ep3(), folderPath: folderB.path);
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
      await repo.selectSource(await ep3(), folderPath: folderB.path);
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

    await repo.selectSource(await ep3(), folderPath: folderB.path);
    await repo.clearSource(await ep3());

    expect(a.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);
  });

  test('a removed override-target folder falls back to priority', () async {
    await dropEp3(folderA);
    await dropEp3(folderB);
    await sync.sync([folderA.path, folderB.path]);
    await repo.selectSource(await ep3(), folderPath: folderB.path);
    expect((await ep3()).fileRef, contains('/B/'));

    // Folder B is removed (its files drop out of the cache). The inert override
    // row remains but resolution falls back to the only surviving source.
    await db.removeFolderAndFiles(folderB.path);
    final e = await ep3();
    expect(e.hasMultipleSources, isFalse);
    expect(e.fileRef, '${folderA.path}/Cowboy Bebop - 03.mkv');
  });
}
