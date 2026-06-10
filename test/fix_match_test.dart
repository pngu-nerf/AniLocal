import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/sync/fix_match_service.dart';
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

Map<String, dynamic> _m(int id, String romaji, int episodes) => {
  'id': id,
  'title': {'romaji': romaji, 'english': null, 'native': null},
  'format': 'TV',
  'episodes': episodes,
  'coverImage': {'extraLarge': 'http://a/$id.jpg', 'large': 'http://a/$id.jpg'},
};

void main() {
  late Directory dir;
  late CacheDatabase db;
  late LibrarySync sync;
  late FixMatchService fixMatch;
  late DriftLibraryRepository repo;

  // Distinct size per file -> distinct content fingerprint.
  Future<File> touch(String name, int size) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    await f.writeAsString('x' * size);
    return f;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_fix_');
    db = CacheDatabase(NativeDatabase.memory());
    final artDir = await Directory('${dir.path}/.art').create();
    final mock = MockClient((req) async {
      if (req.method == 'POST') {
        final q = (jsonDecode(req.body)['variables']['search'] as String)
            .toLowerCase();
        final media = <Map<String, dynamic>>[];
        if (q.contains('sakamoto')) {
          media
            ..add(_m(100, 'Sakamoto Days', 11))
            ..add(_m(200, 'Sakamoto Days 2nd Season', 11));
        } else if (q.contains('hunter')) {
          media.add(_m(300, 'Hunter x Hunter', 148));
        } else if (q.contains('punch')) {
          media.add(_m(400, 'One Punch Man Specials', 6));
        }
        return _page(media);
      }
      return http.Response.bytes([1, 2, 3], 200); // art
    });
    final anilist = AniListClient(httpClient: mock);
    sync = LibrarySync(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      matcher: SeriesMatcher(anilist: anilist),
      cache: db,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
    );
    fixMatch = FixMatchService(
      anilist: anilist,
      art: ArtCache(httpClient: mock, directory: () async => artDir),
      cache: db,
    );
    repo = DriftLibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<Series> candidate(String query, int id) async {
    final c = await fixMatch.searchCandidates(query);
    return c.firstWhere((s) => s.anilistId == id);
  }

  test('override survives a rescan (seam #5)', () async {
    final f = await touch('Sakamoto Days - 12.mkv', 1200);
    await sync.sync([dir.path]); // auto -> S1 (#100)
    expect((await repo.episodesFor(100)).length, 1);

    await fixMatch.assignFile(
      filePath: f.path,
      chosen: await candidate('Sakamoto Days', 200),
      anchoredEpisode: 1,
    );
    expect(await repo.episodesFor(100), isEmpty);
    expect((await repo.episodesFor(200)).length, 1);

    await sync.sync([dir.path]); // rescan must NOT clobber the override

    expect((await repo.episodesFor(200)).length, 1);
    expect(await repo.episodesFor(100), isEmpty);
  });

  test('unmatched file -> assign (the OPM Specials case)', () async {
    final f = await touch('Some Untitled Special - 01.mkv', 500);
    await sync.sync([dir.path]); // no candidates -> unmatched
    expect((await repo.unmatchedFiles()).length, 1);

    await fixMatch.assignFile(
      filePath: f.path,
      chosen: await candidate('One Punch Man', 400),
    );

    expect(await repo.unmatchedFiles(), isEmpty);
    expect((await repo.allSeries()).single.anilistId, 400);
  });

  test('wrongly-matched file -> reassign', () async {
    final f = await touch('Sakamoto Days - 03.mkv', 700);
    await sync.sync([dir.path]); // auto -> S1 (#100)
    expect((await repo.allSeries()).single.anilistId, 100);

    await fixMatch.assignFile(
      filePath: f.path,
      chosen: await candidate('Sakamoto Days', 200),
      anchoredEpisode: 3,
    );

    expect((await repo.allSeries()).single.anilistId, 200);
  });

  test(
    'Sakamoto split: anchored truth, both display modes, non-11 offset',
    () async {
      final paths = [
        (await touch('Sakamoto Days - 12.mkv', 1201)).path,
        (await touch('Sakamoto Days - 13.mkv', 1202)).path,
        (await touch('Sakamoto Days - 14.mkv', 1203)).path,
      ];
      await sync.sync([dir.path]); // auto -> S1
      final s2 = await candidate('Sakamoto Days', 200);

      // Continuous display, real prior-season count = 11.
      await fixMatch.assignRange(
        filePaths: paths,
        chosen: s2,
        anchorStart: 1,
        continuousOffset: 11,
        displayContinuous: true,
      );
      expect(
        (await repo.episodesFor(200)).map((e) => e.number),
        [12, 13, 14],
        reason: 'continuous = anchored(1,2,3) + prior count(11)',
      );

      // Faithful display: AniList-relative positions.
      await fixMatch.assignRange(
        filePaths: paths,
        chosen: s2,
        anchorStart: 1,
        displayContinuous: false,
      );
      expect((await repo.episodesFor(200)).map((e) => e.number), [1, 2, 3]);

      // Non-11 prior count (e.g. a 24-episode S1) must compute correctly.
      await fixMatch.assignRange(
        filePaths: paths,
        chosen: s2,
        anchorStart: 1,
        continuousOffset: 24,
        displayContinuous: true,
      );
      expect((await repo.episodesFor(200)).map((e) => e.number), [25, 26, 27]);
    },
  );

  test('override survives a file move (new path, same size+mtime)', () async {
    final a = await touch('Sakamoto Days - 12.mkv', 1500);
    await sync.sync([dir.path]);
    await fixMatch.assignFile(
      filePath: a.path,
      chosen: await candidate('Sakamoto Days', 200),
      anchoredEpisode: 1,
    );

    // A real move is a rename: new path, identical inode -> identical size+mtime.
    final newDir = await Directory('${dir.path}/Season 2').create();
    final b = await a.rename('${newDir.path}/Sakamoto Days - 12.mkv');

    await sync.sync([dir.path]); // re-scans; sync never touches overrides

    final eps = await repo.episodesFor(200);
    expect(
      eps.map((e) => e.fileRef),
      [b.path],
      reason: 'override followed the file by fingerprint, not path',
    );
    expect(await repo.episodesFor(100), isEmpty);
  });

  test('a split (range override) survives a rescan', () async {
    final paths = [
      (await touch('Sakamoto Days - 12.mkv', 2201)).path,
      (await touch('Sakamoto Days - 13.mkv', 2202)).path,
    ];
    await sync.sync([dir.path]); // auto -> S1
    await fixMatch.assignRange(
      filePaths: paths,
      chosen: await candidate('Sakamoto Days', 200),
      anchorStart: 1,
      continuousOffset: 11,
      displayContinuous: true,
    );
    expect((await repo.episodesFor(200)).map((e) => e.number), [12, 13]);

    await sync.sync([dir.path]); // rescan must NOT clobber the split

    expect((await repo.episodesFor(200)).map((e) => e.number), [12, 13]);
    expect(await repo.episodesFor(100), isEmpty);
  });

  test('continuously-numbered single entry needs no override', () async {
    await touch('Hunter x Hunter - 100.mkv', 900);
    await sync.sync([dir.path]); // auto -> single HxH entry (#300)

    final eps = await repo.episodesFor(300);
    expect(eps.single.number, 100, reason: 'auto-match just counts up');
    expect(await db.allOverrideRows(), isEmpty, reason: 'no split needed');
  });
}
