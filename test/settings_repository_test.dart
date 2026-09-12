import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/drift_settings_repository.dart';
import 'package:anilocal/data/cache/skip_view_source.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/source_preference.dart';
import 'package:anilocal/domain/repositories/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

CachedSeriesRow _series(int id) => CachedSeriesRow(
  seriesId: id,
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
  seriesId: id,
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
    repo = DriftLibraryRepository(
      db,
      skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
    );
    settings = DriftSettingsRepository(db);
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
    expect(await settings.loadPanelWidth(), 300);
  });

  test('each setting round-trips', () async {
    await settings.setAutoPlayNext(false);
    await settings.setSkipMode(SkipMode.auto);
    await settings.setMissingEnabled(false);
    await settings.setShowContinueWatching(false);
    await settings.setShowSearchBar(false);
    await settings.setContinueCollapsed(true);
    await settings.setRailFraction(0.45);
    await settings.setPanelWidth(260);
    await settings.setWatchedThreshold(const Duration(minutes: 2, seconds: 30));

    expect(await settings.loadAutoPlayNext(), isFalse);
    expect(await settings.loadSkipMode(), SkipMode.auto);
    expect(await settings.loadMissingEnabled(), isFalse);
    expect(await settings.loadShowContinueWatching(), isFalse);
    expect(await settings.loadShowSearchBar(), isFalse);
    expect(await settings.loadContinueCollapsed(), isTrue);
    expect(await settings.loadRailFraction(), 0.45);
    expect(await settings.loadPanelWidth(), 260);
    expect(
      await settings.loadWatchedThreshold(),
      const Duration(minutes: 2, seconds: 30),
    );
  });

  test('the source-order encoder round-trips through the REAL store', () async {
    // `token:1,token:0` — one encoder for both lists. Pinned against the
    // database rather than a fake, so the persisted format has a regression
    // test; duplicates and junk in a hand-edited row are tolerated.
    const order = [
      SourcePreference(token: 'kitsu'),
      SourcePreference(token: 'anilist', enabled: false),
    ];
    await settings.setMetadataSourceOrder(order);
    expect(await settings.loadMetadataSourceOrder(), order);
    await settings.setSkipSourceOrder(order.reversed.toList());
    expect(await settings.loadSkipSourceOrder(), order.reversed.toList());

    await db.setSetting('skip_source_order', 'a:1,a:0,b:banana,,c');
    expect(await settings.loadSkipSourceOrder(), const [
      SourcePreference(token: 'a'),
      SourcePreference(token: 'b'),
      SourcePreference(token: 'c'),
    ]);
  });

  test('min-skip length is clamped to [0, 600s] on read AND write', () async {
    await settings.setMinSkipLength(const Duration(minutes: 30));
    expect(await settings.loadMinSkipLength(), minSkipLengthMax);
    await db.setSetting('min_skip_length_seconds', '-5');
    expect(await settings.loadMinSkipLength(), Duration.zero);
  });

  test('booleans read both encodings, write one', () async {
    // corroborate_skips was once written as 1/0; an existing install has it.
    await db.setSetting('corroborate_skips', '1');
    expect(await settings.loadCorroborateSkips(), isTrue);
    await settings.setCorroborateSkips(false);
    expect(await db.getSetting('corroborate_skips'), 'false');
    expect(await settings.loadCorroborateSkips(), isFalse);
  });

  test('a client id is trimmed; blank means none', () async {
    await settings.setSourceClientId('mal', '  abc  ');
    expect(await settings.loadSourceClientId('mal'), 'abc');
    await settings.setSourceClientId('mal', '   ');
    expect(await settings.loadSourceClientId('mal'), isNull);
  });

  test('layout sizes are clamped on load like every other setting', () async {
    await db.setSetting('theater_rail_fraction', '0.9');
    expect(await settings.loadRailFraction(), railFractionMax);
    await db.setSetting('continue_panel_width', '5');
    expect(await settings.loadPanelWidth(), panelWidthMin);
    await db.setSetting('continue_panel_width', 'nonsense');
    expect(await settings.loadPanelWidth(), panelWidthDefault);
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
