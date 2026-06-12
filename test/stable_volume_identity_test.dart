import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/folders/volume_resolver.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fake [VolumeResolver]: configured by `infoByPath` (longest-prefix match →
/// VolumeInfo) and `mountById` (uuid → current mount, null = not mounted). Lets
/// a test simulate a volume remounting under a different name with no diskutil.
class _FakeVolumeResolver implements VolumeResolver {
  final Map<String, VolumeInfo> infoByPath = {};
  final Map<String, String?> mountById = {};

  @override
  Future<VolumeInfo?> infoForPath(String path) async {
    String? best;
    for (final k in infoByPath.keys) {
      if (path == k || path.startsWith('$k/')) {
        if (best == null || k.length > best.length) best = k;
      }
    }
    return best == null ? null : infoByPath[best];
  }

  @override
  Future<String?> mountPointForVolumeId(String volumeId) async =>
      mountById[volumeId];
}

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
  group('pure path helpers', () {
    test('rebaseToFolderRelative picks the longest matching folder prefix', () {
      final folders = ['/Volumes/Anime', '/Volumes/Anime/movies'];
      expect(rebaseToFolderRelative('/Volumes/Anime/Bebop/ep01.mkv', folders), (
        folderPath: '/Volumes/Anime',
        relativePath: 'Bebop/ep01.mkv',
      ));
      // Nested folder wins (more specific).
      expect(
        rebaseToFolderRelative('/Volumes/Anime/movies/akira.mkv', folders),
        (folderPath: '/Volumes/Anime/movies', relativePath: 'akira.mkv'),
      );
      // A file directly at the folder root has an empty relative path.
      expect(rebaseToFolderRelative('/Volumes/Anime', folders), (
        folderPath: '/Volumes/Anime',
        relativePath: '',
      ));
      // No matching folder -> (parent, basename) fallback (row preserved).
      expect(rebaseToFolderRelative('/elsewhere/x.mkv', folders), (
        folderPath: '/elsewhere',
        relativePath: 'x.mkv',
      ));
    });

    test('volumeSubpathOf strips the mount prefix', () {
      expect(volumeSubpathOf('/Volumes/Anime', '/Volumes/Anime'), '');
      expect(
        volumeSubpathOf('/Volumes/Anime/shows', '/Volumes/Anime'),
        'shows',
      );
    });

    test('resolveFolderPath: fast path uses an existing stored path', () async {
      final dir = await Directory.systemTemp.createTemp('anilocal_fp_');
      final resolver = _FakeVolumeResolver();
      // Stored path exists -> returned directly, resolver never consulted.
      expect(
        await resolveFolderPath(
          storedPath: dir.path,
          volumeId: 'VOL',
          volumeSubpath: '',
          resolver: resolver,
        ),
        dir.path,
      );
      await dir.delete();
    });

    test('resolveFolderPath: follows a remounted volume by id', () async {
      final resolver = _FakeVolumeResolver()..mountById['VOL'] = '/Volumes/New';
      expect(
        await resolveFolderPath(
          storedPath: '/Volumes/Old/shows', // gone
          volumeId: 'VOL',
          volumeSubpath: 'shows',
          resolver: resolver,
        ),
        '/Volumes/New/shows',
      );
    });

    test('resolveFolderPath: null when the volume is not mounted', () async {
      final resolver = _FakeVolumeResolver(); // VOL not in mountById
      expect(
        await resolveFolderPath(
          storedPath: '/Volumes/Old', // gone
          volumeId: 'VOL',
          volumeSubpath: '',
          resolver: resolver,
        ),
        isNull,
      );
    });
  });

  group('scan with volume identity', () {
    late Directory dir;
    late CacheDatabase db;
    late DriftLibraryRepository repo;
    late LibrarySync sync;
    late _FakeVolumeResolver fake;

    Future<void> touch(String path, int size) async {
      final f = File(path);
      await f.create(recursive: true);
      await f.writeAsString('x' * size);
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_vol_');
      db = CacheDatabase(NativeDatabase.memory());
      fake = _FakeVolumeResolver();
      repo = DriftLibraryRepository(db, resolver: fake);
      final artDir = await Directory('${dir.path}/.art').create();
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          final q = (jsonDecode(req.body)['variables']['search'] as String)
              .toLowerCase();
          if (q.contains('cowboy')) return _page([_m(1, 'Cowboy Bebop')]);
          return _page(const []);
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
        resolver: fake,
      );
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('a volume that remounts under a new name does NOT churn', () async {
      // "VOL1" is mounted at mountA (a real dir we can walk).
      final mountA = '${dir.path}/MountA';
      await touch('$mountA/Cowboy Bebop/Cowboy Bebop - 01.mkv', 100);
      await touch('$mountA/Cowboy Bebop/Cowboy Bebop - 02.mkv', 200);
      fake.infoByPath[mountA] = VolumeInfo(
        volumeId: 'VOL1',
        mountPoint: mountA,
      );
      fake.mountById['VOL1'] = mountA;

      await db.insertFolder(mountA); // stable identity = mountA
      final first = await sync.sync([mountA]);
      expect(first.processed, 2);
      expect((await repo.allSeries()).length, 1);

      // The folder got bound to its volume (UUID + subpath = volume root).
      final bound = (await db.allFolderRows()).single;
      expect(bound.volumeId, 'VOL1');
      expect(bound.volumeSubpath, '');

      // --- Remount under a new name: rename the dir (same files, same
      // size+mtime), and the volume now reports mountB. The stored path
      // (mountA) is gone, so resolution must follow VOL1 to mountB.
      final mountB = '${dir.path}/MountB';
      await Directory(mountA).rename(mountB);
      fake.mountById['VOL1'] = mountB;

      final second = await sync.sync([mountA]); // same stable identity

      expect(second.unchanged, 2, reason: 'remount must not re-identify');
      expect(second.processed, 0);
      expect(second.anilistLookups, 0, reason: 'no AniList refetch on remount');
      expect(second.removed, 0, reason: 'same files at a new mount, not gone');
      expect((await repo.allSeries()).length, 1);

      // The repository resolves fileRefs to the CURRENT mount, so the file the
      // player would open actually exists.
      final eps = await repo.episodesFor(1);
      expect(eps, hasLength(2));
      expect(eps.first.fileRef, startsWith(mountB));
      expect(File(eps.first.fileRef).existsSync(), isTrue);
    });

    test('an unmounted volume preserves the cache (nothing removed)', () async {
      final mountA = '${dir.path}/MountA';
      await touch('$mountA/Cowboy Bebop/Cowboy Bebop - 01.mkv', 100);
      fake.infoByPath[mountA] = VolumeInfo(
        volumeId: 'VOL1',
        mountPoint: mountA,
      );
      fake.mountById['VOL1'] = mountA;
      await db.insertFolder(mountA);
      await sync.sync([mountA]);
      expect((await repo.allSeries()).length, 1);

      // Volume goes offline: stored path gone AND the volume isn't mounted.
      await Directory(mountA).rename('${dir.path}/unplugged');
      fake.mountById['VOL1'] = null;

      final summary = await sync.sync([mountA]);
      expect(
        summary.unreadableFolders,
        contains(mountA),
        reason: 'an offline volume surfaces, it is not silently dropped',
      );
      expect(summary.removed, 0, reason: 'offline != deleted — preserve it');
      expect((await repo.allSeries()).length, 1, reason: 'library kept');
    });

    test('an internal (non-volume) folder works and stays unbound', () async {
      // dir.path is a temp dir, not under /Volumes; the fake reports no volume.
      await touch('${dir.path}/lib/Cowboy Bebop - 01.mkv', 100);
      await db.insertFolder('${dir.path}/lib');
      final s = await sync.sync(['${dir.path}/lib']);
      expect(s.processed, 1);
      expect(
        (await db.allFolderRows()).single.volumeId,
        isNull,
        reason: 'internal folders need no UUID binding',
      );

      final s2 = await sync.sync(['${dir.path}/lib']);
      expect(s2.unchanged, 1);
      expect(s2.anilistLookups, 0);
      expect((await repo.episodesFor(1)).single.fileRef, endsWith('- 01.mkv'));
    });
  });
}
