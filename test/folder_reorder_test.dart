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
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
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

  Future<File> dropEp3(Directory folder) async {
    final f = File('${folder.path}/Cowboy Bebop - 03.mkv');
    await f.create(recursive: true);
    await f.writeAsString('x' * 800);
    return f;
  }

  Future<Episode> ep3() async =>
      (await repo.episodesFor(1)).firstWhere((e) => e.number == 3);

  // Reorder helper: priority = list order (index 0 = top).
  Future<void> reorder(List<Directory> order) =>
      repo.reorderFolders([for (final d in order) LibraryFolder(path: d.path)]);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('anilocal_reorder_');
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
      aniSkip: AniSkipClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      ),
    );
    repo = DriftLibraryRepository(db);
    await db.insertFolder(folderA.path); // sortOrder 0
    await db.insertFolder(folderB.path); // sortOrder 1
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('reorder re-resolves an Automatic default source — no rescan', () async {
    await dropEp3(folderA);
    await dropEp3(folderB);
    await sync.sync([folderA.path, folderB.path]);
    expect((await ep3()).fileRef, contains('/A/'), reason: 'A starts on top');

    // Drag B above A. NO sync between here and the assert: re-resolution must
    // come from the cached order alone.
    await reorder([folderB, folderA]);

    expect(
      (await ep3()).fileRef,
      '${folderB.path}/Cowboy Bebop - 03.mkv',
      reason: 'the newly-top folder is now the preferred default source',
    );
  });

  test(
    'a manual per-episode source pin survives a reorder (seam #5)',
    () async {
      await dropEp3(folderA);
      await dropEp3(folderB);
      await sync.sync([folderA.path, folderB.path]);

      // Pin to A (which also happens to be the current default).
      await repo.selectSource(await ep3(), folderPath: folderA.path);

      // Promote B to the top. An Automatic episode would now prefer B — but the
      // pin to A must hold; a global reorder never clobbers a per-episode pin.
      await reorder([folderB, folderA]);

      final e = await ep3();
      expect(e.fileRef, '${folderA.path}/Cowboy Bebop - 03.mkv');
      expect(e.pinnedSourceFolder, folderA.path);
    },
  );

  test('only un-pinned episodes re-resolve; pinned ones do not', () async {
    // Two episodes, both in both folders. Pin ep 3 to B; leave ep 5 Automatic.
    await dropEp3(folderA);
    await dropEp3(folderB);
    final a5 = File('${folderA.path}/Cowboy Bebop - 05.mkv');
    final b5 = File('${folderB.path}/Cowboy Bebop - 05.mkv');
    await a5.writeAsString('x' * 800);
    await b5.writeAsString('x' * 800);
    await sync.sync([folderA.path, folderB.path]);

    Future<Episode> ep(int n) async =>
        (await repo.episodesFor(1)).firstWhere((e) => e.number == n);
    await repo.selectSource(await ep(3), folderPath: folderB.path);

    await reorder([folderB, folderA]); // B to the top

    expect((await ep(3)).fileRef, contains('/B/'), reason: 'pinned, stays B');
    expect(
      (await ep(5)).fileRef,
      contains('/B/'),
      reason: 'Automatic, re-resolves to the new top folder',
    );
  });

  test('the new order persists (survives a relaunch)', () async {
    await reorder([folderB, folderA]);

    // A fresh repository on the same store = relaunch; order is read back from
    // the persistent sortOrder column.
    final reopened = DriftLibraryRepository(db);
    final order = (await reopened.watchedFolders()).map((f) => f.path).toList();
    expect(order, [folderB.path, folderA.path]);
  });
}
