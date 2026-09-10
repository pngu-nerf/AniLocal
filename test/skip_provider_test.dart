import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
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
  });

  @override
  final String token;
  final EpisodeSkips? windows;
  final MetadataFailure? failure;
  final bool configured;
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
  Future<bool> isConfigured() async => configured;

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    calls++;
    onLookup?.call(lookup);
    if (failure != null) throw SkipException('$token down', failure: failure!);
    return windows;
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
        loadCorroborateSkips: () async => corroborate,
      ).sync([dir.path]);
    }

    test('the first source WITH DATA wins, and is recorded', () async {
      // "No data" is not failure: partial coverage is normal, so an empty
      // answer must fall through silently rather than end the chain.
      final empty = _FakeSkip('aniskip');
      final has = _FakeSkip('chapters', windows: _op());

      await scanWith([empty, has]);

      final row = (await db.allSkipRows()).single;
      expect(row.introEndMs, 90000);
      expect(
        row.source,
        'chapters',
        reason: 'provenance must say who actually answered',
      );
      expect(empty.calls, 1, reason: 'asked first, had nothing');
    });

    test('a FAILING source falls through to the next', () async {
      final down = _FakeSkip('aniskip', failure: MetadataFailure.service);
      final up = _FakeSkip('chapters', windows: _op());

      await scanWith([down, up]);

      expect((await db.allSkipRows()).single.source, 'chapters');
    });

    test('an unconfigured source is never asked', () async {
      final needsKey = _FakeSkip(
        'animeskip',
        configured: false,
        windows: _op(),
      );
      final ok = _FakeSkip('aniskip', windows: _op());

      await scanWith([needsKey, ok]);

      expect(needsKey.calls, 0);
      expect((await db.allSkipRows()).single.source, 'aniskip');
    });

    test('no source with data means NO row, not an empty one', () async {
      await scanWith([_FakeSkip('aniskip'), _FakeSkip('chapters')]);

      expect(await db.allSkipRows(), isEmpty);
    });

    test('REFRESH carries the file path too — the backfill path', () async {
      // The one that actually matters for an existing library: a scan only
      // fetches skips for files it is already reprocessing, so refresh is the
      // ONLY way a newly-added local source reaches episodes already scanned.
      // Without the file path a chapters-style source is silently inert here.
      await scanWith([_FakeSkip('aniskip')]); // scan first, no skip data
      expect(await db.allSkipRows(), isEmpty);

      late SkipLookup seen;
      final spy = _FakeSkip(
        'chapters',
        windows: _op(),
        onLookup: (l) => seen = l,
      );
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
        skipProviders: [spy],
      ).refreshMetadata();

      expect(
        seen.filePath,
        endsWith('Cowboy Bebop - 01.mkv'),
        reason: 'a local source cannot read a file it is never given',
      );
      expect((await db.allSkipRows()).single.source, 'chapters');
    });

    test('cross-check OFF stops at the first source with data', () async {
      // The cheap path: no reason to call a network source once the file's own
      // chapters have answered.
      final first = _FakeSkip('chapters', windows: _op());
      final second = _FakeSkip('aniskip', windows: _op());

      await scanWith([first, second]);

      expect(second.calls, 0, reason: 'never asked');
      expect((await db.allSkipRows()).single.introConfidence, 0);
    });

    test('cross-check ON asks everyone and records agreement', () async {
      final a = _FakeSkip('chapters', windows: _op());
      final b = _FakeSkip('aniskip', windows: _op());

      await scanWith([a, b], corroborate: true);

      expect(b.calls, 1, reason: 'asked, so its answer can be compared');
      final row = (await db.allSkipRows()).single;
      expect(row.introConfidence, 1, reason: 'corroborated');
      expect(row.source, 'chapters', reason: 'top source still supplies times');
    });

    test('cross-check ON records a conflict when they disagree', () async {
      final a = _FakeSkip('chapters', windows: _op());
      final b = _FakeSkip(
        'aniskip',
        windows: const EpisodeSkips(
          intro: SkipRange(
            start: Duration(seconds: 600),
            end: Duration(seconds: 690),
          ),
        ),
      );

      await scanWith([a, b], corroborate: true);

      expect((await db.allSkipRows()).single.introConfidence, -1);
    });

    test('a source with NO data is not counted as disagreement', () async {
      // The rule that keeps auto-skip alive on a partially-covered library.
      final a = _FakeSkip('chapters', windows: _op());
      final silent = _FakeSkip('aniskip'); // asked, nothing to say

      await scanWith([a, silent], corroborate: true);

      final row = (await db.allSkipRows()).single;
      expect(silent.calls, 1, reason: 'it WAS asked');
      expect(
        row.introConfidence,
        0,
        reason: 'single source, not a conflict — silence is not dissent',
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
}
