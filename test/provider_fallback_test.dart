import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/series_identity.dart';
import 'package:anilocal/data/kitsu/kitsu_client.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/metadata/kitsu_metadata_provider.dart';
import 'package:anilocal/data/metadata/metadata_provider.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/external_ids.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/source_preference.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A provider whose behaviour each test dictates outright — the point here is
/// the CHAIN and the IDENTITY rules, not any real API's wire format.
class _FakeProvider implements MetadataProvider {
  _FakeProvider(
    this.token, {
    this.results = const [],
    this.failure,
    this.configured = true,
    this.fallbackOnly = false,
  });

  @override
  final String token;
  final List<Series> results;
  final MetadataFailure? failure;
  final bool configured;
  final bool fallbackOnly;

  int searchCalls = 0;

  @override
  String get displayName => token;

  @override
  String get idNamespace => token;

  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;

  @override
  Future<bool> isConfigured() async => configured;

  @override
  bool get isFallbackOnly => fallbackOnly;

  @override
  Future<List<Series>> searchCandidates(
    String title, {
    int perPage = 10,
  }) async {
    searchCalls++;
    if (failure != null) {
      throw MetadataException('$token is down', failure: failure!);
    }
    return results;
  }

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) async {
    if (failure != null) {
      throw MetadataException('$token is down', failure: failure!);
    }
    return results;
  }
}

Series _series(String title, ExternalIds ids, {int? seriesId}) => Series(
  seriesId: seriesId ?? ids.anilist ?? ids.kitsu ?? 1,
  externalIds: ids,
  titles: Titles(romaji: title),
);

void main() {
  late CacheDatabase db;

  setUp(() => db = CacheDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('the fallback chain', () {
    test('a failing source falls through to the next', () async {
      final down = _FakeProvider('anilist', failure: MetadataFailure.service);
      final up = _FakeProvider(
        'kitsu',
        results: [
          _series('Cowboy Bebop', const ExternalIds(kitsu: 265, mal: 1)),
        ],
      );

      final result = await SeriesMatcher(
        providers: [down, up],
      ).match('Cowboy Bebop');

      expect(result.series?.titles.romaji, 'Cowboy Bebop');
      expect(down.searchCalls, 1);
      expect(up.searchCalls, 1);
    });

    test(
      'an UNCONFIGURED source is skipped, not counted as a failure',
      () async {
        final needsKey = _FakeProvider('mal', configured: false);
        final ok = _FakeProvider(
          'anilist',
          results: [_series('Trigun', const ExternalIds(anilist: 6))],
        );

        final result = await SeriesMatcher(
          providers: [needsKey, ok],
        ).match('Trigun');

        expect(result.series?.externalIds.anilist, 6);
        expect(needsKey.searchCalls, 0, reason: 'never asked');
      },
    );

    test('a genuine NO-MATCH stops the chain — it is an answer', () async {
      // Otherwise a title would be shopped around until some source guessed
      // something, which is worse than reporting no match.
      final empty = _FakeProvider('anilist', results: const []);
      final other = _FakeProvider(
        'kitsu',
        results: [_series('Wrong Show', const ExternalIds(kitsu: 9))],
      );

      final result = await SeriesMatcher(
        providers: [empty, other],
      ).match('Nonexistent Show');

      expect(result.series, isNull);
      expect(other.searchCalls, 0, reason: 'the first source already answered');
    });

    test('all sources down throws, carrying the failure kind', () async {
      final a = _FakeProvider('anilist', failure: MetadataFailure.service);
      final b = _FakeProvider('kitsu', failure: MetadataFailure.connection);

      await expectLater(
        SeriesMatcher(providers: [a, b]).match('x'),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.failure,
            'failure',
            // The LAST attempt's cause: it is the one that actually left us
            // with nothing.
            MetadataFailure.connection,
          ),
        ),
      );
    });

    test(
      'a FALLBACK-ONLY source never leads, whatever the user saved',
      () async {
        // Jikan is MAL's data through a volunteer proxy measured at ~30%
        // availability. Worth having when everything else is down; not worth
        // building a library's metadata on — so it cannot be dragged to the top.
        final jikan = _FakeProvider(
          'mal',
          fallbackOnly: true,
          results: [_series('Cowboy Bebop', const ExternalIds(mal: 1))],
        );
        final anilist = _FakeProvider(
          'anilist',
          results: [_series('Cowboy Bebop', const ExternalIds(anilist: 21))],
        );

        final result = await SeriesMatcher(
          providers: [jikan, anilist],
          // The user explicitly put the fallback first.
          loadOrder: () async => const [
            SourcePreference(token: 'mal'),
            SourcePreference(token: 'anilist'),
          ],
        ).match('Cowboy Bebop');

        expect(result.series?.externalIds.anilist, 21, reason: 'AniList led');
        expect(
          jikan.searchCalls,
          0,
          reason: 'not even asked while AniList works',
        );
      },
    );

    test('but a fallback-only source IS used when the others fail', () async {
      final anilist = _FakeProvider(
        'anilist',
        failure: MetadataFailure.service,
      );
      final jikan = _FakeProvider(
        'mal',
        fallbackOnly: true,
        results: [_series('Cowboy Bebop', const ExternalIds(mal: 1))],
      );

      final result = await SeriesMatcher(
        providers: [anilist, jikan],
      ).match('Cowboy Bebop');

      expect(result.series?.externalIds.mal, 1);
    });

    test(
      'when EVERY source is fallback-only, one of them still answers',
      () async {
        // The rule must not deadlock a build that ships only such sources.
        final a = _FakeProvider(
          'mal',
          fallbackOnly: true,
          results: [_series('Cowboy Bebop', const ExternalIds(mal: 9))],
        );

        final result = await SeriesMatcher(
          providers: [a],
        ).match('Cowboy Bebop');

        expect(result.series?.externalIds.mal, 9);
      },
    );

    test('no configured source is a FAILURE, never a no-match', () async {
      // A no-match would flip files to confirmed-unmatched and they would never
      // be retried automatically — the wrong outcome for a config problem.
      await expectLater(
        SeriesMatcher(
          providers: [_FakeProvider('mal', configured: false)],
        ).match('x'),
        throwsA(isA<MetadataException>()),
      );
    });
  });

  group('the real thing: Kitsu answers when AniList is down', () {
    test('a file is identified, and lands on the AniList identity', () async {
      // AniList is 403ing exactly as it is in production today.
      final anilist = AniListMetadataProvider(
        AniListClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'errors': [
                  {'message': 'The AniList API has been temporarily disabled'},
                ],
                'data': null,
              }),
              403,
            ),
          ),
        ),
      );
      final kitsu = KitsuMetadataProvider(
        KitsuClient(
          httpClient: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'data': [
                    {
                      'id': '1',
                      'type': 'anime',
                      'attributes': {
                        'canonicalTitle': 'Cowboy Bebop',
                        'titles': {'en_jp': 'Cowboy Bebop'},
                        'subtype': 'TV',
                        'episodeCount': 26,
                      },
                      'relationships': {
                        'mappings': {
                          'data': [
                            {'type': 'mappings', 'id': 'm1'},
                          ],
                        },
                      },
                    },
                  ],
                  'included': [
                    {
                      'id': 'm1',
                      'type': 'mappings',
                      'attributes': {
                        'externalSite': 'anilist/anime',
                        'externalId': '21',
                      },
                    },
                  ],
                }),
              ),
              200,
              headers: {'content-type': 'application/vnd.api+json'},
            ),
          ),
        ),
      );

      final result = await SeriesMatcher(
        providers: [anilist, kitsu],
      ).match('Cowboy Bebop');

      expect(result.series, isNotNull, reason: 'Kitsu carried the lookup');

      // Because Kitsu reported the AniList id alongside its own, the show
      // resolves to the SEEDED identity — the same id AniList would have given
      // it. A library identified during the outage therefore needs no repair
      // when AniList returns.
      final id = await db.ensureSeriesId(result.series!.externalIds);
      expect(id, 21);
      expect(isProviderSeededSeriesId(id), isTrue);
      expect((await db.externalIdsBySeriesId())[21]?.kitsu, 1);
    });
  });

  group('ensureSeriesId', () {
    test('an AniList id becomes the series id directly — no minting', () async {
      final id = await db.ensureSeriesId(const ExternalIds(anilist: 21));

      expect(id, 21, reason: 'the provider-seeded band IS the AniList id');
      expect(isProviderSeededSeriesId(id), isTrue);
    });

    test('a show with no AniList id gets a minted identity', () async {
      final id = await db.ensureSeriesId(const ExternalIds(kitsu: 5000));

      expect(isMintedSeriesId(id), isTrue);
      expect(id, greaterThanOrEqualTo(kMintedSeriesIdBase));
    });

    test('minted ids are unique and monotonic', () async {
      final a = await db.ensureSeriesId(const ExternalIds(kitsu: 1));
      final b = await db.ensureSeriesId(const ExternalIds(kitsu: 2));

      expect(b, greaterThan(a));
    });

    test('the same ids resolve to the same identity, every time', () async {
      final a = await db.ensureSeriesId(const ExternalIds(kitsu: 77, mal: 88));
      final b = await db.ensureSeriesId(const ExternalIds(kitsu: 77, mal: 88));

      expect(b, a);
    });

    test('THE SPLIT-BRAIN CASE: a show is never minted twice', () async {
      // Kitsu identifies the show first — no AniList id, so an id is minted.
      final minted = await db.ensureSeriesId(
        const ExternalIds(kitsu: 265, mal: 1),
      );
      expect(isMintedSeriesId(minted), isTrue);

      // Watch progress accrues under that identity.
      await db.upsertWatchState(
        WatchStateRow(
          seriesId: minted,
          episode: 3,
          resumePositionMs: 4242,
          durationMs: 1440000,
          watched: false,
          watchedManual: false,
          updatedAtMs: 1,
        ),
      );

      // Later AniList is healthy and returns the SAME show. Its answer carries
      // an AniList id we have never seen — but also the MAL id we already know.
      final resolved = await db.ensureSeriesId(
        const ExternalIds(anilist: 1, mal: 1),
      );

      expect(
        resolved,
        minted,
        reason:
            'matched on the MAL id both sources publish — a second identity '
            'here would strand the watch progress under an orphaned id',
      );
      expect((await db.watchStateFor(minted, 3))!.resumePositionMs, 4242);

      // And the AniList id is now recorded against that same identity.
      expect((await db.externalIdsBySeriesId())[minted]?.anilist, 1);
    });

    test('two matching shows are NOT merged — the lower id wins', () async {
      // Two identities that nothing yet connects: one known by its AniList id,
      // the other only by a Kitsu id.
      final a = await db.ensureSeriesId(const ExternalIds(anilist: 10));
      final b = await db.ensureSeriesId(const ExternalIds(kitsu: 500));
      expect(a, isNot(b));
      expect(b, greaterThan(a), reason: 'b was minted, a is seeded');

      // Now an answer arrives carrying BOTH ids — they were the same show all
      // along. Merging would move sacred rows on the fill path, which seam #5
      // forbids and which could clobber a fix-match unrecoverably. So the
      // LOWEST matching id wins the mapping and the other row is left intact.
      final resolved = await db.ensureSeriesId(
        const ExternalIds(anilist: 10, kitsu: 500),
      );

      expect(
        resolved,
        a,
        reason: 'lowest of the two matches, deterministically',
      );

      final all = await db.externalIdsBySeriesId();
      expect(
        all[b]?.kitsu,
        500,
        reason:
            'b KEEPS its kitsu id — re-pointing it would be a merge, and '
            'merging on the fill path can clobber a fix-match',
      );
      expect(all[a]?.kitsu, isNull, reason: 'a does not steal it');
      expect(all[a]?.anilist, 10, reason: 'what a already owned is intact');
    });

    test('empty ids are rejected rather than silently minting', () async {
      await expectLater(
        db.ensureSeriesId(ExternalIds.empty),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
