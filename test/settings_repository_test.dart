import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/drift_settings_repository.dart';
import 'package:anilocal/domain/repositories/settings_repository.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
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
  coverImagePath: null,
);

CachedFileRow _file(int id) => CachedFileRow(
  folderPath: '/lib/s$id',
  relativePath: 'ep1.mkv',
  fileSize: 1,
  modifiedAtMs: 1,
  anilistId: id,
  episodeNumber: 1,
  parsedTitle: 'Series $id',
  matchScore: 1,
  releaseGroup: null,
  pendingIdentification: false,
);

void main() {
  late CacheDatabase db;
  late DriftLibraryRepository repo;
  late DriftSettingsRepository settings;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    settings = DriftSettingsRepository(db, showPreferences: repo);
  });
  tearDown(() => db.close());

  test('defaults on a fresh store match the shipped defaults', () async {
    expect(await settings.loadContinueCollapsed(), isFalse);
    expect(await settings.loadAutoPlayNext(), isTrue);
    expect(await settings.loadSkipMode(), SkipMode.button);
    expect(await settings.loadWatchedThreshold(), const Duration(seconds: 90));
    expect(await settings.loadMissingEnabled(), isTrue);
    expect(await settings.loadHideNextEpisode(), isFalse);
    expect(await settings.loadShowContinueWatching(), isTrue);
    expect(await settings.loadShowSearchBar(), isTrue);
    expect(await settings.loadRailFraction(), 0.30);
    expect(await settings.loadPanelFraction(), 0.22);
  });

  test('each setting round-trips', () async {
    await settings.setAutoPlayNext(false);
    await settings.setSkipMode(SkipMode.auto);
    await settings.setMissingEnabled(false);
    await settings.setShowContinueWatching(false);
    await settings.setShowSearchBar(false);
    await settings.setContinueCollapsed(true);
    await settings.setRailFraction(0.45);
    await settings.setPanelFraction(0.15);
    await settings.setWatchedThreshold(const Duration(minutes: 2, seconds: 30));

    expect(await settings.loadAutoPlayNext(), isFalse);
    expect(await settings.loadSkipMode(), SkipMode.auto);
    expect(await settings.loadMissingEnabled(), isFalse);
    expect(await settings.loadShowContinueWatching(), isFalse);
    expect(await settings.loadShowSearchBar(), isFalse);
    expect(await settings.loadContinueCollapsed(), isTrue);
    expect(await settings.loadRailFraction(), 0.45);
    expect(await settings.loadPanelFraction(), 0.15);
    expect(
      await settings.loadWatchedThreshold(),
      const Duration(minutes: 2, seconds: 30),
    );
  });

  test('watched-threshold is clamped to [0, 9:59] on load', () async {
    await settings.setWatchedThreshold(const Duration(minutes: 20));
    expect(await settings.loadWatchedThreshold(), watchedThresholdMax);
    await settings.setWatchedThreshold(Duration.zero);
    expect(await settings.loadWatchedThreshold(), Duration.zero);
  });

  test(
    'setHideNextEpisode persists the flag AND applies to every show',
    () async {
      await db.applySync(
        seriesUpserts: [_series(1), _series(2)],
        fileUpserts: [_file(1), _file(2)],
        removedKeys: const [],
      );

      await settings.setHideNextEpisode(true);
      expect(await settings.loadHideNextEpisode(), isTrue);
      expect((await repo.preferencesFor(1)).nextEpisodeHidden, isTrue);
      expect((await repo.preferencesFor(2)).nextEpisodeHidden, isTrue);

      await settings.setHideNextEpisode(false);
      expect(await settings.loadHideNextEpisode(), isFalse);
      expect((await repo.preferencesFor(1)).nextEpisodeHidden, isFalse);
      expect((await repo.preferencesFor(2)).nextEpisodeHidden, isFalse);
    },
  );
}
