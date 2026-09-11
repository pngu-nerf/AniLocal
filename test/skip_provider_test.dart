import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/folders/volume_resolver.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:anilocal/data/skip/aniskip_skip_provider.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:anilocal/domain/models/source_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A skip source whose behaviour each test dictates.
class _FakeSkip implements SkipProvider {
  _FakeSkip(
    this.token, {
    this.windows,
    this.failure,
    this.configured = true,
    this.onLookup,
    this.answerable = true,
  });

  @override
  final String token;
  final EpisodeSkips? windows;
  final MetadataFailure? failure;
  final bool configured;
  final bool answerable;
  final void Function(SkipLookup)? onLookup;

  int calls = 0;

  @override
  String get displayName => token;
  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;
  @override
  bool canAnswer(SkipLookup lookup) => answerable;
  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    calls++;
    onLookup?.call(lookup);
    if (failure != null) throw SkipException('$token down', failure: failure!);
    return windows;
  }
}

/// A [VolumeResolver] a test configures directly: `mountById` says where a
/// volume UUID is mounted RIGHT NOW (null = not mounted), so a test can move a
/// library folder to a new mount name without diskutil.
class _FakeVolumeResolver implements VolumeResolver {
  final Map<String, String?> mountById = {};

  @override
  Future<VolumeInfo?> infoForPath(String path) async => null;

  @override
  Future<String?> mountPointForVolumeId(String volumeId) async =>
      mountById[volumeId];
}

/// The answer a given source recorded for episode 1, or null if never asked.
extension on List<SkipSourceAnswerRow> {
  SkipSourceAnswerRow? from(String source) {
    for (final a in this) {
      if (a.source == source) return a;
    }
    return null;
  }
}

EpisodeSkips _op() => const EpisodeSkips(
  intro: SkipRange(start: Duration.zero, end: Duration(seconds: 90)),
);

/// The AniList payload the scan needs to identify the file at all.
http.Response _anilistPage() => http.Response(
  jsonEncode({
    'data': {
      'Page': {
        'media': [
          {
            'id': 1,
            'idMal': 4224,
            'title': {'romaji': 'Cowboy Bebop'},
            'format': 'TV',
            'episodes': 26,
            'relations': {'edges': []},
          },
        ],
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('the skip family is its own thing', () {
    test(
      'AniSkip returns null without a MAL id — that is not a failure',
      () async {
        // Partial coverage is the NORM for skip data. A series with no MAL id
        // simply has nothing to look up; treating that as an error would knock
        // the source out of the chain for every episode after it.
        var called = false;
        final provider = AniSkipSkipProvider(
          AniSkipClient(
            httpClient: MockClient((_) async {
              called = true;
              return http.Response('', 500);
            }),
          ),
        );

        final result = await provider.fetchSkips(
          const SkipLookup(seriesId: 1, episode: 1),
        );

        expect(result, isNull);
        expect(called, isFalse, reason: 'the guard is before any request');
      },
    );

    test('skip tokens are their own namespace', () {
      // The two families are ordered independently, so a token only has to be
      // unique within its own list.
      expect(kAniSkipSource, 'aniskip');
      expect(
        {
          kAniSkipSource,
          kChaptersSource,
          kAnimeSkipSource,
          kFingerprintSource,
        }.length,
        4,
      );
    });
  });

  group('ordering applies to skip sources too', () {
    test('the saved order decides who is asked first', () {
      final a = _FakeSkip('aniskip');
      final b = _FakeSkip('chapters');

      final ordered = applySourceOrder(
        [a, b],
        (p) => p.token,
        const [
          SourcePreference(token: 'chapters'),
          SourcePreference(token: 'aniskip'),
        ],
      );

      expect(ordered.map((p) => p.token), ['chapters', 'aniskip']);
    });

    test('a disabled skip source is dropped from the chain', () {
      final a = _FakeSkip('aniskip');
      final b = _FakeSkip('chapters');

      final ordered = applySourceOrder(
        [a, b],
        (p) => p.token,
        const [
          SourcePreference(token: 'aniskip', enabled: false),
          SourcePreference(token: 'chapters'),
        ],
      );

      expect(ordered.map((p) => p.token), ['chapters']);
    });
  });

  group('the chain, through the real fill path', () {
    late Directory dir;
    late CacheDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_skipchain_');
      db = CacheDatabase(NativeDatabase.memory());
      final f = File('${dir.path}/Cowboy Bebop - 01.mkv');
      await f.create(recursive: true);
      await f.writeAsString('xxxxx');
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<void> scanWith(
      List<SkipProvider> providers, {
      bool corroborate = false,
      VolumeResolver? resolver,
      List<String>? folders,
    }) async {
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage();
        return http.Response.bytes([1, 2, 3], 200);
      });
      await LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          providers: [AniListMetadataProvider(AniListClient(httpClient: mock))],
        ),
        cache: db,
        art: ArtCache(
          httpClient: mock,
          directory: () async => Directory('${dir.path}/.art')..createSync(),
        ),
        skipProviders: providers,
        resolver: resolver,
      ).sync(folders ?? [dir.path]);
    }

    Future<void> refreshWith(
      List<SkipProvider> providers, {
      bool corroborate = false,
      VolumeResolver? resolver,
      List<String>? folders,
      List<SourcePreference> order = const [],
    }) async {
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage();
        return http.Response.bytes([1, 2, 3], 200);
      });
      await LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          providers: [AniListMetadataProvider(AniListClient(httpClient: mock))],
        ),
        cache: db,
        art: ArtCache(
          httpClient: mock,
          directory: () async => Directory('${dir.path}/.art')..createSync(),
        ),
        skipProviders: providers,
        loadSkipOrder: () async => order,
        resolver: resolver,
      ).refreshMetadata();
    }

    test(
      'a folder whose volume REMOUNTED still hands sources the real file',
      () async {
        // The cache keys a file by its folder's STABLE identity (the path the
        // folder was added under), and both fill paths used to build the skip
        // lookup's file path from that identity. A removable volume that comes
        // back under another `/Volumes` name therefore handed the local chapters
        // source a dangling path — and, before `canAnswer` checked for the file,
        // recorded "no chapters" for the whole drive. The lookup must carry the
        // CURRENT mount.
        final stored = dir.path; // the identity the folder was added under
        final remounted = '${dir.path}-remounted';
        await db.insertFolder(stored);
        await scanWith([]);
        await db.bindFolderVolume(stored, 'VOL-1', '');
        await Directory(stored).rename(remounted);
        addTearDown(() async {
          // The group's tearDown deletes `dir`; put it back so that succeeds.
          if (Directory(remounted).existsSync()) {
            await Directory(remounted).rename(stored);
          }
        });
        final resolver = _FakeVolumeResolver()..mountById['VOL-1'] = remounted;

        // Refresh: the file is unchanged and was never asked about.
        final seenOnRefresh = <SkipLookup>[];
        await refreshWith([
          _FakeSkip('chapters', onLookup: seenOnRefresh.add),
        ], resolver: resolver);
        expect(seenOnRefresh, hasLength(1));
        expect(
          seenOnRefresh.single.filePath,
          '$remounted/Cowboy Bebop - 01.mkv',
          reason: 'refresh builds the path from the CURRENT mount',
        );
        expect(File(seenOnRefresh.single.filePath!).existsSync(), isTrue);

        // Scan: a file that arrives AFTER the remount is a delta under the
        // stable folder identity, and its lookup must resolve the same way.
        await File('$remounted/Cowboy Bebop - 02.mkv').writeAsString('xxxxx');
        final seenOnScan = <SkipLookup>[];
        await scanWith(
          [_FakeSkip('aniskip', onLookup: seenOnScan.add)],
          resolver: resolver,
          folders: [stored],
        );
        final ep2 = seenOnScan.where((l) => l.episode == 2).toList();
        expect(ep2, hasLength(1));
        expect(
          ep2.single.filePath,
          '$remounted/Cowboy Bebop - 02.mkv',
          reason: 'scan builds the path from the CURRENT mount',
        );
      },
    );

    test('every source is asked, and what each SAID is recorded', () async {
      // Since v19 the fill path stores raw answers rather than a verdict, so
      // "had nothing" is a recorded fact and not an absence. That is what lets
      // the read path decide later without ever re-asking.
      final empty = _FakeSkip('aniskip');
      final has = _FakeSkip('chapters', windows: _op());

      await scanWith([empty, has]);

      final answers = await db.allSkipAnswers();
      expect(answers.length, 2);
      expect(answers.from('chapters')!.introEndMs, 90000);
      expect(
        answers.from('aniskip')!.introStartMs,
        isNull,
        reason: 'asked, had nothing — a row of nulls, not a missing row',
      );
      expect(empty.calls, 1);
    });

    test('a FAILING source records NOTHING, so it is retried', () async {
      // The distinction the contract rests on: "had nothing" is a row of
      // nulls and is never asked again; a failure is no row at all.
      final down = _FakeSkip('aniskip', failure: MetadataFailure.service);
      final up = _FakeSkip('chapters', windows: _op());

      await scanWith([down, up]);

      final answers = await db.allSkipAnswers();
      expect(answers.from('chapters')!.introEndMs, 90000);
      expect(answers.from('aniskip'), isNull, reason: 'failure leaves no row');
    });

    test(
      'an unconfigured source is never asked, and records nothing',
      () async {
        // It must not leave a row of nulls either: that would read as "asked,
        // had nothing" and stop it being asked once a key is finally pasted.
        final needsKey = _FakeSkip(
          'animeskip',
          configured: false,
          windows: _op(),
        );
        final ok = _FakeSkip('aniskip', windows: _op());

        await scanWith([needsKey, ok]);

        expect(needsKey.calls, 0);
        final answers = await db.allSkipAnswers();
        expect(answers.from('animeskip'), isNull);
        expect(answers.from('aniskip')!.introEndMs, 90000);
      },
    );

    test('no source with data still records that both were asked', () async {
      await scanWith([_FakeSkip('aniskip'), _FakeSkip('chapters')]);

      final answers = await db.allSkipAnswers();
      expect(answers.length, 2, reason: 'both answered "nothing"');
      expect(answers.every((a) => a.introStartMs == null), isTrue);
    });

    test('REFRESH carries the file path too — the backfill path', () async {
      // The one that actually matters for an existing library: a scan only
      // fetches skips for files it is already reprocessing, so refresh is the
      // ONLY way a newly-added local source reaches episodes already scanned.
      // Without the file path a chapters-style source is silently inert here.
      await scanWith([_FakeSkip('aniskip')]); // scan first, no skip data
      expect((await db.allSkipAnswers()).from('chapters'), isNull);

      late SkipLookup seen;
      final spy = _FakeSkip(
        'chapters',
        windows: _op(),
        onLookup: (l) => seen = l,
      );
      await refreshWith([spy]);

      expect(
        seen.filePath,
        endsWith('Cowboy Bebop - 01.mkv'),
        reason: 'a local source cannot read a file it is never given',
      );
      expect((await db.allSkipAnswers()).from('chapters')!.introEndMs, 90000);
    });

    test('EVERY source is asked, whatever cross-checking is set to', () async {
      // v19 moved cross-checking to the read path, so the fill path no longer
      // knows about it. Asking everyone once is what makes toggling the
      // setting instant later — the answers are already on disk.
      final first = _FakeSkip('chapters', windows: _op());
      final second = _FakeSkip('aniskip', windows: _op());

      await scanWith([first, second]);

      expect(second.calls, 1, reason: 'asked even with cross-checking off');
      expect((await db.allSkipAnswers()).length, 2);
    });

    test('"could not try" records NOTHING, so it is retried', () async {
      // The distinction that keeps the cross-map useful. AniSkip asked before
      // its MAL id is known has nothing to ask WITH — recording that as "I
      // have no data" would stop it ever being asked again, so the id the
      // cross-map supplies later could never reach it. The suite caught
      // exactly this when the answer table first landed.
      final notYet = _FakeSkip('aniskip', windows: _op(), answerable: false);

      await scanWith([notYet]);

      expect(notYet.calls, 0, reason: 'not even attempted');
      expect(
        await db.allSkipAnswers(),
        isEmpty,
        reason: 'no row at all — "nothing" would be a lie that sticks',
      );

      // Once it CAN answer, the refresh picks it up.
      final now = _FakeSkip('aniskip', windows: _op());
      await refreshWith([now]);
      expect((await db.allSkipAnswers()).from('aniskip')!.introEndMs, 90000);
    });

    test(
      'a CHANGED file does not re-ask sources that already answered',
      () async {
        // The scan reprocesses a file whose size or mtime changed. Before v19's
        // contract was applied to this path too, it re-asked every source for
        // it — one wasted request per source per changed file, and (worse) a
        // fresh "nothing" answer could not clear a stale window.
        final chapters = _FakeSkip('chapters', windows: _op());
        await scanWith([chapters]);
        final afterFirst = chapters.calls;

        await File(
          '${dir.path}/Cowboy Bebop - 01.mkv',
        ).writeAsString('yyyyyyyy');
        await scanWith([chapters]); // reprocessed: the fingerprint changed

        expect(chapters.calls, afterFirst, reason: 'its answer is on file');
      },
    );

    test('a source already answered is never asked again', () async {
      // What keeps refresh incremental now that there is no resolution key:
      // presence of a row IS the record that we asked.
      final chapters = _FakeSkip('chapters', windows: _op());
      await scanWith([chapters]);
      final afterScan = chapters.calls;

      await refreshWith([chapters]);

      expect(chapters.calls, afterScan, reason: 'nothing new to ask');
    });

    test('the floor is a LIVE read — no rescan needed to change it', () async {
      // Applied where Episode is built rather than when the row is written, so
      // raising or lowering it takes effect at once instead of needing the
      // whole library re-scanned.
      await scanWith([
        _FakeSkip(
          'chapters',
          windows: const EpisodeSkips(
            intro: SkipRange(start: Duration.zero, end: Duration(seconds: 8)),
          ),
        ),
      ]);
      expect((await db.allSkipAnswers()).single.introEndMs, 8000);

      var floor = Duration.zero;
      final repo = DriftLibraryRepository(db);
      repo.loadMinSkipLength = () async => floor;
      repo.loadActiveSkipSources = () async => const ['chapters'];

      final seriesId = (await db.allSkipAnswers()).single.seriesId;
      expect(
        (await repo.episodesFor(seriesId)).single.introSkip,
        isNotNull,
        reason: 'no floor set — the window is offered',
      );

      floor = const Duration(seconds: 30);
      expect(
        (await repo.episodesFor(seriesId)).single.introSkip,
        isNull,
        reason: 'same cached row, new floor, immediately hidden',
      );
    });

    test('the lookup carries the MAL id resolved for the series', () async {
      late SkipLookup seen;
      final spy = _FakeSkip('aniskip', onLookup: (l) => seen = l);

      await scanWith([spy]);

      expect(seen.malId, 4224, reason: 'from the AniList payload');
      expect(seen.episode, 1);
    });
  });

  group('SkipLookup carries what every source needs', () {
    test('one request shape serves network AND local sources', () {
      // AniSkip keys off the MAL id; chapters key off the file; fingerprinting
      // needs the siblings. Threading three signatures through the fill path
      // would be worse than one request a source can ignore parts of.
      const lookup = SkipLookup(
        seriesId: 21,
        episode: 3,
        malId: 4224,
        filePath: '/lib/ep3.mkv',
        siblingPaths: ['/lib/ep1.mkv', '/lib/ep2.mkv'],
        episodeLength: Duration(minutes: 24),
      );

      expect(lookup.malId, 4224);
      expect(lookup.filePath, endsWith('ep3.mkv'));
      expect(lookup.siblingPaths, hasLength(2));
      expect(lookup.episodeLength?.inMinutes, 24);
    });
  });

  group('resolution happens on the READ path', () {
    // The v19 guarantee, and the reason the hand-bumped generation counter is
    // gone: nothing derived is stored, so changing how skips are resolved
    // takes effect on the next READ. No refresh, no rescan, nothing to
    // invalidate and therefore nothing to forget to invalidate.
    late Directory dir;
    late CacheDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_readpath_');
      db = CacheDatabase(NativeDatabase.memory());
      final f = File('${dir.path}/Cowboy Bebop - 01.mkv');
      await f.create(recursive: true);
      await f.writeAsString('xxxxx');
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    /// Two sources that disagree about the intro by more than the overlap rule
    /// tolerates, plus an outro only the second one knows.
    Future<int> seed() async {
      final mock = MockClient((req) async {
        if (req.method == 'POST') return _anilistPage();
        return http.Response.bytes([1, 2, 3], 200);
      });
      await LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(
          providers: [AniListMetadataProvider(AniListClient(httpClient: mock))],
        ),
        cache: db,
        art: ArtCache(
          httpClient: mock,
          directory: () async => Directory('${dir.path}/.art')..createSync(),
        ),
        skipProviders: [
          _FakeSkip('chapters', windows: _op()),
          _FakeSkip(
            'aniskip',
            windows: const EpisodeSkips(
              intro: SkipRange(
                start: Duration(seconds: 600),
                end: Duration(seconds: 690),
              ),
              outro: SkipRange(
                start: Duration(seconds: 1300),
                end: Duration(seconds: 1390),
              ),
            ),
          ),
        ],
      ).sync([dir.path]);
      return (await db.allSkipAnswers()).first.seriesId;
    }

    test('REORDERING sources changes the times with no refresh', () async {
      final seriesId = await seed();
      var order = const ['chapters', 'aniskip'];
      final repo = DriftLibraryRepository(db);
      repo.loadActiveSkipSources = () async => order;

      expect(
        (await repo.episodesFor(seriesId)).single.introSkip?.end,
        const Duration(seconds: 90),
        reason: 'chapters is on top',
      );

      order = const ['aniskip', 'chapters']; // a drag in Settings, nothing else
      expect(
        (await repo.episodesFor(seriesId)).single.introSkip?.end,
        const Duration(seconds: 690),
        reason: 'the new top source supplies the times, immediately',
      );
    });

    test(
      'TOGGLING cross-checking changes the verdict with no refresh',
      () async {
        final seriesId = await seed();
        var corroborate = false;
        final repo = DriftLibraryRepository(db);
        repo.loadActiveSkipSources = () async => const ['chapters', 'aniskip'];
        repo.loadCorroborateSkips = () async => corroborate;

        expect(
          (await repo.episodesFor(seriesId)).single.introConfidence,
          SkipConfidence.single,
          reason: 'off: the top answer simply stands',
        );

        corroborate = true;
        expect(
          (await repo.episodesFor(seriesId)).single.introConfidence,
          SkipConfidence.conflicting,
          reason: 'on: the two disagree about where the theme is',
        );
      },
    );

    test('switching a source OFF stops using it, immediately', () async {
      final seriesId = await seed();
      var order = const ['chapters', 'aniskip'];
      final repo = DriftLibraryRepository(db);
      repo.loadActiveSkipSources = () async => order;

      expect((await repo.episodesFor(seriesId)).single.introSkip, isNotNull);

      order = const ['aniskip']; // chapters unchecked
      expect(
        (await repo.episodesFor(seriesId)).single.introSkip?.start,
        const Duration(seconds: 600),
        reason: 'its stored answer is ignored while it is off',
      );
    });

    test('each window takes the best source that HAS it', () async {
      // The old write path stopped at the first source with any data, so an
      // episode whose top source knew only the intro lost an outro a lower
      // source could have supplied. Resolving per window fixes that.
      final seriesId = await seed();
      final repo = DriftLibraryRepository(db);
      repo.loadActiveSkipSources = () async => const ['chapters', 'aniskip'];

      final ep = (await repo.episodesFor(seriesId)).single;
      expect(
        ep.introSkip?.end,
        const Duration(seconds: 90),
        reason: 'chapters',
      );
      expect(
        ep.outroSkip?.start,
        const Duration(seconds: 1300),
        reason: 'only aniskip has an outro — it is no longer lost',
      );
    });

    test('a LEGACY answer is a last resort and never corroborates', () async {
      // What a v18 row migrates to when its provenance was never recorded.
      final seriesId = await seed();
      await db.upsertSkipAnswer(
        SkipSourceAnswerRow(
          seriesId: seriesId,
          episode: 1,
          source: kLegacySource,
          introStartMs: 0,
          introEndMs: 90000,
          askedAtMs: 0,
        ),
      );
      final repo = DriftLibraryRepository(db);
      repo.loadCorroborateSkips = () async => true;

      // With NO known source enabled, the legacy window still shows.
      repo.loadActiveSkipSources = () async => const [];
      var ep = (await repo.episodesFor(seriesId)).single;
      expect(ep.introSkip?.end, const Duration(seconds: 90));
      expect(
        ep.introConfidence,
        SkipConfidence.single,
        reason: 'unknown provenance cannot corroborate anything',
      );

      // With a known source enabled, the legacy answer steps aside entirely —
      // including as a corroborating voice for the chapters window it matches.
      repo.loadActiveSkipSources = () async => const ['chapters'];
      ep = (await repo.episodesFor(seriesId)).single;
      expect(ep.introSkip?.end, const Duration(seconds: 90));
      expect(ep.introConfidence, SkipConfidence.single);
    });
  });
}
