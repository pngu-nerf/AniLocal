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
  late Directory dir;
  late CacheDatabase db;
  late LibrarySync sync;
  late DriftLibraryRepository repo;

  Future<File> touch(String name, int size) async {
    final f = File('${dir.path}/$name');
    await f.create(recursive: true);
    await f.writeAsString('x' * size);
    return f;
  }

  Future<Episode> episode(int anilistId, int number) async =>
      (await repo.episodesFor(anilistId)).firstWhere((e) => e.number == number);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_watch_');
    db = CacheDatabase(NativeDatabase.memory());
    final artDir = await Directory('${dir.path}/.art').create();
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
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('resume position round-trips', () async {
    await touch('Cowboy Bebop - 03.mkv', 800);
    await sync.sync([dir.path]);

    await repo.saveProgress(
      await episode(1, 3),
      position: const Duration(minutes: 14, seconds: 32),
      duration: const Duration(minutes: 24),
    );

    expect(
      (await episode(1, 3)).resumePosition,
      const Duration(minutes: 14, seconds: 32),
    );
  });

  test(
    'watch state is keyed by episode identity and survives a file move',
    () async {
      final a = await touch('Cowboy Bebop - 03.mkv', 800);
      await sync.sync([dir.path]);
      await repo.saveProgress(
        await episode(1, 3),
        position: const Duration(minutes: 14, seconds: 32),
        duration: const Duration(minutes: 24),
      );

      // Move (rename): new path, SAME episode identity (anilistId 1, ep 3).
      final moved = await Directory('${dir.path}/moved').create();
      final b = await a.rename('${moved.path}/Cowboy Bebop - 03.mkv');
      await sync.sync([dir.path]); // re-scan; sync never touches watch_state

      final after = await episode(1, 3);
      expect(after.fileRef, b.path, reason: 'now playing the moved file');
      expect(
        after.resumePosition,
        const Duration(minutes: 14, seconds: 32),
        reason: 'resume keyed by episode identity, not file path',
      );
    },
  );

  test(
    'setWatched marks watched, clears resume, leaves continue-watching',
    () async {
      await touch('Cowboy Bebop - 03.mkv', 800);
      await sync.sync([dir.path]);
      await repo.saveProgress(
        await episode(1, 3),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 24),
      );
      expect((await repo.continueWatching()).length, 1);

      await repo.setWatched(await episode(1, 3), watched: true);

      final after = await episode(1, 3);
      expect(after.watched, isTrue);
      expect(after.resumePosition, Duration.zero);
      expect(await repo.continueWatching(), isEmpty);
    },
  );

  test(
    'setWatchedManual marks watched WITHOUT clearing the resume position',
    () async {
      await touch('Cowboy Bebop - 03.mkv', 800);
      await sync.sync([dir.path]);
      await repo.saveProgress(
        await episode(1, 3),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 24),
      );

      await repo.setWatchedManual(await episode(1, 3), watched: true);

      final after = await episode(1, 3);
      expect(after.watched, isTrue);
      expect(
        after.resumePosition,
        const Duration(minutes: 10),
        reason: 'manual toggle leaves progress untouched',
      );
      // Watched ⇒ still out of continue-watching even though resume survived.
      expect(await repo.continueWatching(), isEmpty);
    },
  );

  test('a manual override WINS over the auto/threshold path', () async {
    await touch('Cowboy Bebop - 03.mkv', 800);
    await sync.sync([dir.path]);

    // User manually marks UNWATCHED…
    await repo.setWatchedManual(await episode(1, 3), watched: false);
    // …then the threshold tries to auto-mark watched — must be a no-op.
    await repo.setWatched(await episode(1, 3), watched: true);
    expect(
      (await episode(1, 3)).watched,
      isFalse,
      reason: 'manual unwatched beats the auto threshold',
    );

    // And the reverse: manual watched survives an auto "unwatched" attempt.
    await repo.setWatchedManual(await episode(1, 3), watched: true);
    await repo.setWatched(await episode(1, 3), watched: false);
    expect((await episode(1, 3)).watched, isTrue);
  });

  test('saveProgress does NOT clobber a manual watched override', () async {
    await touch('Cowboy Bebop - 03.mkv', 800);
    await sync.sync([dir.path]);
    await repo.setWatchedManual(await episode(1, 3), watched: true);

    // Simulate resume ticking while (re)playing a manually-watched episode.
    await repo.saveProgress(
      await episode(1, 3),
      position: const Duration(minutes: 12),
      duration: const Duration(minutes: 24),
    );

    final after = await episode(1, 3);
    expect(
      after.watched,
      isTrue,
      reason: 'the sticky override survives a progress save',
    );
    expect(after.resumePosition, const Duration(minutes: 12));
  });

  test(
    'clearProgress dismisses from continue-watching, NOT marking watched',
    () async {
      await touch('Cowboy Bebop - 03.mkv', 800);
      await sync.sync([dir.path]);
      await repo.saveProgress(
        await episode(1, 3),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 24),
      );
      expect((await repo.continueWatching()).length, 1);

      await repo.clearProgress(await episode(1, 3));

      expect(await repo.continueWatching(), isEmpty);
      final after = await episode(1, 3);
      expect(after.watched, isFalse, reason: 'dismissed, not finished');
      expect(after.resumePosition, Duration.zero);
    },
  );

  test('app settings persist a value (the collapsed choice)', () async {
    expect(await db.getSetting('continue_collapsed'), isNull);
    await db.setSetting('continue_collapsed', 'true');
    expect(await db.getSetting('continue_collapsed'), 'true');
    await db.setSetting('continue_collapsed', 'false');
    expect(await db.getSetting('continue_collapsed'), 'false');
  });

  test(
    'continue-watching surfaces an in-progress episode with its series',
    () async {
      await touch('Cowboy Bebop - 05.mkv', 800);
      await sync.sync([dir.path]);
      await repo.saveProgress(
        await episode(1, 5),
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 24),
      );

      final cw = await repo.continueWatching();
      expect(cw.single.series.anilistId, 1);
      expect(cw.single.episode.number, 5);
      expect(cw.single.episode.resumePosition, const Duration(minutes: 5));
    },
  );
}
