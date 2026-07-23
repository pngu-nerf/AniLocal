import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

CachedSeriesRow _series(int id) => CachedSeriesRow(
  anilistId: id,
  romaji: 'Series $id',
  english: null,
  nativeTitle: null,
  format: 'TV',
  episodeCount: 12,
  coverImageUrl: null,
  coverImagePath: '/art/$id.jpg',
);

CachedFileRow _file(int id, int ep) => CachedFileRow(
  folderPath: '/lib/s$id',
  relativePath: 'ep$ep.mkv',
  fileSize: 1,
  modifiedAtMs: ep,
  anilistId: id,
  episodeNumber: ep,
  parsedTitle: 'Series $id',
  matchScore: 1,
  releaseGroup: null,
  pendingIdentification: false,
);

void main() {
  late CacheDatabase db;
  late DriftLibraryRepository repo;

  // The fill path (a scan): re-upserts series + files, never watch/prefs.
  Future<void> fill() => db.applySync(
    seriesUpserts: [_series(1)],
    fileUpserts: [_file(1, 1)],
    removedKeys: const [],
  );

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() => db.close());

  test('all-default when nothing is stored', () async {
    final p = await repo.preferencesFor(1);
    expect(p.pictureMode, PictureMode.normal);
    expect(p.nextEpisodeHidden, isFalse);
    expect(await repo.allPreferences(), isEmpty);
  });

  test('prefs round-trip and surface on the Series projection', () async {
    await fill();
    await repo.setPictureMode(1, PictureMode.blur);
    await repo.setNextEpisodeHidden(1, hidden: true);

    final p = await repo.preferencesFor(1);
    expect(p.pictureMode, PictureMode.blur);
    expect(p.nextEpisodeHidden, isTrue);

    final s = (await repo.allSeries()).firstWhere((s) => s.anilistId == 1);
    expect(s.pictureMode, PictureMode.blur);
    expect(s.nextEpisodeHidden, isTrue);
  });

  test('setting one pref preserves the other', () async {
    await repo.setPictureMode(1, PictureMode.removed);
    await repo.setNextEpisodeHidden(1, hidden: true);
    // The next-hidden write must not reset the picture mode…
    expect((await repo.preferencesFor(1)).pictureMode, PictureMode.removed);
    // …and a picture-mode write must not reset next-hidden.
    await repo.setPictureMode(1, PictureMode.normal);
    expect((await repo.preferencesFor(1)).nextEpisodeHidden, isTrue);
  });

  test(
    'setAllNextEpisodeHidden overwrites every show, preserving picture mode',
    () async {
      await db.applySync(
        seriesUpserts: [_series(1), _series(2)],
        fileUpserts: [_file(1, 1), _file(2, 1)],
        removedKeys: const [],
      );
      // Divergent starting state: show 1 hidden + blurred, show 2 shown.
      await repo.setPictureMode(1, PictureMode.blur);
      await repo.setNextEpisodeHidden(1, hidden: true);
      await repo.setNextEpisodeHidden(2, hidden: false);

      // Global ON → all become hidden; picture modes untouched.
      await repo.setAllNextEpisodeHidden(hidden: true);
      expect((await repo.preferencesFor(1)).nextEpisodeHidden, isTrue);
      expect((await repo.preferencesFor(2)).nextEpisodeHidden, isTrue);
      expect((await repo.preferencesFor(1)).pictureMode, PictureMode.blur);

      // Global OFF → all become shown.
      await repo.setAllNextEpisodeHidden(hidden: false);
      expect((await repo.preferencesFor(1)).nextEpisodeHidden, isFalse);
      expect((await repo.preferencesFor(2)).nextEpisodeHidden, isFalse);
      expect((await repo.preferencesFor(1)).pictureMode, PictureMode.blur);
    },
  );

  test(
    'preferences are SACRED across a rescan (no fill-path writer)',
    () async {
      await fill();
      await repo.setPictureMode(1, PictureMode.blur);
      await repo.setNextEpisodeHidden(1, hidden: true);

      await fill(); // rescan re-runs the fill path

      final s = (await repo.allSeries()).firstWhere((s) => s.anilistId == 1);
      expect(s.pictureMode, PictureMode.blur, reason: 'survives rescan');
      expect(s.nextEpisodeHidden, isTrue, reason: 'survives rescan');
    },
  );
}
