import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

CachedSeriesRow _series(int id, {int? episodeCount}) => CachedSeriesRow(
  anilistId: id,
  romaji: 'Series $id',
  english: null,
  nativeTitle: null,
  format: 'TV',
  episodeCount: episodeCount,
  coverImageUrl: null,
  coverImagePath: null,
);

CachedFileRow _file(int anilistId, int ep) => CachedFileRow(
  folderPath: '/lib/s$anilistId',
  relativePath: 'ep$ep.mkv',
  fileSize: 1,
  modifiedAtMs: ep,
  anilistId: anilistId,
  episodeNumber: ep,
  parsedTitle: 'Series $anilistId',
  matchScore: 1,
  releaseGroup: null,
);

void main() {
  late CacheDatabase db;
  late DriftLibraryRepository repo;

  Future<void> seed(List<CachedSeriesRow> series, List<CachedFileRow> files) =>
      db.applySync(
        seriesUpserts: series,
        fileUpserts: files,
        removedKeys: const [],
      );

  Future<void> markWatched(int anilistId, int ep) => db.upsertWatchState(
    WatchStateRow(
      anilistId: anilistId,
      episode: ep,
      resumePositionMs: 0,
      durationMs: 0,
      watched: true,
      updatedAtMs: ep,
    ),
  );

  Future<Episode> ep(int anilistId, int number) async =>
      (await repo.episodesFor(anilistId)).firstWhere((e) => e.number == number);

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });

  tearDown(() => db.close());

  group('nextEpisode (within-season only)', () {
    test('returns the next anchored episode in the same series', () async {
      await seed(
        [_series(1, episodeCount: 12)],
        [_file(1, 1), _file(1, 2), _file(1, 3)],
      );
      final result = await repo.nextEpisode(await ep(1, 2));
      expect(result, isA<NextEpisode>());
      final next = (result as NextEpisode).episode;
      expect(next.seriesAnilistId, 1);
      expect(next.number, 3);
    });

    test(
      'the last in-library episode returns NoNextEpisode (clean boundary)',
      () async {
        // This is the season-boundary answer today AND the seam where
        // cross-season (the AniList SEQUEL relation) will slot in later.
        await seed(
          [_series(1, episodeCount: 12)],
          [_file(1, 1), _file(1, 2), _file(1, 3)],
        );
        expect(await repo.nextEpisode(await ep(1, 3)), isA<NoNextEpisode>());
      },
    );

    test(
      'does not invent an episode you do not have (gap) -> NoNext',
      () async {
        await seed([_series(1, episodeCount: 12)], [_file(1, 1), _file(1, 2)]);
        expect(await repo.nextEpisode(await ep(1, 2)), isA<NoNextEpisode>());
      },
    );
  });

  group('upNextBySeries', () {
    test(
      'a started series -> the episode after the furthest watched',
      () async {
        await seed(
          [_series(1, episodeCount: 12)],
          [_file(1, 1), _file(1, 2), _file(1, 3)],
        );
        await markWatched(1, 1);
        final up = await repo.upNextBySeries();
        expect(up[1], isNotNull);
        expect(up[1]!.number, 2);
      },
    );

    test('an unstarted series is absent (no watched episodes)', () async {
      await seed([_series(1, episodeCount: 12)], [_file(1, 1), _file(1, 2)]);
      expect((await repo.upNextBySeries()).containsKey(1), isFalse);
    });

    test('a caught-up series is absent (nothing within-season next)', () async {
      await seed([_series(1, episodeCount: 12)], [_file(1, 1), _file(1, 2)]);
      await markWatched(1, 1);
      await markWatched(1, 2); // watched the last one we have
      expect((await repo.upNextBySeries()).containsKey(1), isFalse);
    });
  });
}
