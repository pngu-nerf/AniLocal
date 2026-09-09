import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/kitsu/kitsu_client.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/series_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fixtures follow the SHAPE OF THE REAL API, captured from kitsu.io on
/// 2026-09-08 — including the two details the client depends on: mappings
/// arrive in `included` (not inline on the anime) and are linked through
/// `relationships.mappings.data`.
/// Bytes, not a String, and NO charset — exactly what Kitsu sends. Building it
/// any other way would hide the latin1 fallback this client exists to avoid.
http.Response _page() => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'data': [
        {
          'id': '1',
          'type': 'anime',
          'attributes': {
            'canonicalTitle': 'Cowboy Bebop',
            'titles': {
              'en': 'Cowboy Bebop',
              'en_jp': 'Cowboy Bebop',
              'ja_jp': 'カウボーイビバップ',
            },
            'subtype': 'TV',
            'episodeCount': 26,
            'posterImage': {
              'tiny': 'https://media.kitsu.app/anime/1/tiny.jpg',
              'large': 'https://media.kitsu.app/anime/1/large.jpg',
            },
          },
          'relationships': {
            'mappings': {
              'data': [
                {'type': 'mappings', 'id': '64108'},
                {'type': 'mappings', 'id': '68341'},
                {'type': 'mappings', 'id': '254652'},
              ],
            },
          },
        },
        {
          // A movie, to prove the format vocabulary is normalised.
          'id': '2',
          'type': 'anime',
          'attributes': {
            'canonicalTitle': 'Cowboy Bebop: The Movie',
            'titles': {'en_jp': 'Cowboy Bebop: Tengoku no Tobira'},
            'subtype': 'movie',
            'episodeCount': 1,
            'posterImage': {
              'large': 'https://media.kitsu.app/anime/2/large.jpg',
            },
          },
          'relationships': {
            'mappings': {
              'data': [
                {'type': 'mappings', 'id': '609'},
              ],
            },
          },
        },
      ],
      'included': [
        {
          'id': '64108',
          'type': 'mappings',
          'attributes': {
            'externalSite': 'myanimelist/anime',
            'externalId': '1',
          },
        },
        {
          'id': '68341',
          'type': 'mappings',
          'attributes': {'externalSite': 'anilist/anime', 'externalId': '1'},
        },
        {
          'id': '254652',
          'type': 'mappings',
          'attributes': {'externalSite': 'anidb', 'externalId': '23'},
        },
        {
          'id': '609',
          'type': 'mappings',
          'attributes': {'externalSite': 'trakt', 'externalId': '30857'},
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/vnd.api+json'},
);

void main() {
  group('mapping the response', () {
    test('maps titles, format, episodes and poster', () async {
      final client = KitsuClient(httpClient: MockClient((_) async => _page()));

      final results = await client.searchCandidates('cowboy bebop');

      expect(results.length, 2);
      final bebop = results.first;
      expect(bebop.titles.romaji, 'Cowboy Bebop');
      expect(bebop.titles.native, 'カウボーイビバップ');
      expect(bebop.episodeCount, 26);
      expect(bebop.coverImageRef, contains('large.jpg'));
    });

    test("Kitsu's 'movie' becomes the shared MOVIE token", () async {
      // Series.format renders RAW in the UI, so an un-normalised mix would
      // show `TV` next to `movie` in one library.
      final client = KitsuClient(httpClient: MockClient((_) async => _page()));

      final results = await client.searchCandidates('cowboy');

      expect(results[0].format, kFormatTv);
      expect(results[1].format, kFormatMovie);
    });

    test('resolves EVERY external id from the included mappings', () async {
      // The whole reason for include=mappings: without the AniList and MAL ids
      // here, ensureSeriesId would mint a second identity for a show AniList
      // already named.
      final client = KitsuClient(httpClient: MockClient((_) async => _page()));

      final ids = (await client.searchCandidates('cowboy')).first.externalIds;

      expect(ids.kitsu, 1);
      expect(ids.anilist, 1);
      expect(ids.mal, 1);
      expect(ids.anidb, 23);
    });

    test(
      'an anime with no useful mappings still reports its Kitsu id',
      () async {
        final client = KitsuClient(
          httpClient: MockClient((_) async => _page()),
        );

        final movie = (await client.searchCandidates('cowboy'))[1];

        expect(movie.externalIds.kitsu, 2);
        expect(
          movie.externalIds.anilist,
          isNull,
          reason: 'only a trakt mapping',
        );
      },
    );

    test('asks for mappings on every request', () async {
      late Uri seen;
      final client = KitsuClient(
        httpClient: MockClient((req) async {
          seen = req.url;
          return _page();
        }),
      );

      await client.searchCandidates('x', perPage: 5);

      expect(seen.queryParameters['include'], 'mappings');
      expect(seen.queryParameters['filter[text]'], 'x');
      expect(seen.queryParameters['page[limit]'], '5');
    });

    test('fetchByIds filters by id and chunks a long list', () async {
      final filters = <String>[];
      final client = KitsuClient(
        httpClient: MockClient((req) async {
          filters.add(req.url.queryParameters['filter[id]']!);
          return _page();
        }),
      );

      await client.fetchByIds(List.generate(45, (i) => i + 1));

      expect(filters.length, 3, reason: '45 ids at 20 per page');
      expect(filters.first.split(',').length, 20);
      expect(filters.last.split(',').length, 5);
    });

    test('no ids means no request at all', () async {
      var called = false;
      final client = KitsuClient(
        httpClient: MockClient((_) async {
          called = true;
          return _page();
        }),
      );

      expect(await client.fetchByIds(const []), isEmpty);
      expect(called, isFalse);
    });

    test('an empty result is a no-match, not an error', () async {
      final client = KitsuClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'data': []}), 200),
        ),
      );

      expect(await client.searchCandidates('nonexistent'), isEmpty);
    });
  });

  group('failure attribution', () {
    Future<KitsuException> failureOf(http.Response response) async {
      final client = KitsuClient(httpClient: MockClient((_) async => response));
      try {
        await client.searchCandidates('x');
      } on KitsuException catch (e) {
        return e;
      }
      fail('expected a KitsuException');
    }

    test('a JSON:API error body is Kitsu\'s end', () async {
      final e = await failureOf(
        http.Response(
          jsonEncode({
            'errors': [
              {'title': 'Forbidden', 'detail': 'nope'},
            ],
          }),
          403,
        ),
      );

      expect(e.failure, MetadataFailure.service);
      expect(e.message, contains('nope'));
    });

    test('a 4xx with a non-Kitsu body blames the network path', () async {
      final e = await failureOf(http.Response('<html>blocked</html>', 403));

      expect(e.failure, MetadataFailure.blocked);
    });

    test('5xx is service, 429 is rate limiting', () async {
      expect(
        (await failureOf(http.Response('', 502))).failure,
        MetadataFailure.service,
      );
      expect(
        (await failureOf(http.Response('', 429))).failure,
        MetadataFailure.rateLimited,
      );
    });

    test('a transport failure is the connection', () async {
      final client = KitsuClient(
        httpClient: MockClient(
          (_) async => throw const SocketException('offline'),
        ),
      );

      await expectLater(
        client.searchCandidates('x'),
        throwsA(
          isA<KitsuException>().having(
            (e) => e.failure,
            'failure',
            MetadataFailure.connection,
          ),
        ),
      );
    });

    test(
      'a 200 carrying HTML throws Kitsu\'s type, not FormatException',
      () async {
        final e = await failureOf(http.Response('<html>nope</html>', 200));

        expect(e.message, contains('Malformed'));
      },
    );
  });
}
