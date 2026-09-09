import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/mal/mal_client.dart';
import 'package:anilocal/data/metadata/mal_metadata_provider.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/series_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shapes come from MAL's PUBLISHED OpenAPI spec, not an observed 200 — every
/// success path needs a client ID, and none was available. The ERROR shapes
/// below were probed live against api.myanimelist.net and are verbatim.
///
/// Several details here are deliberate traps the spec warns about:
///   * search nests results under `node`; the detail endpoint does not
///   * `num_episodes: 0` means UNKNOWN, not zero episodes
///   * `alternative_titles.en` is often "" rather than null
///   * `media_type` returns values the official enum omits (`tv_special`)
http.Response _searchPage() => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'data': [
        {
          'node': {
            'id': 1,
            'title': 'Cowboy Bebop',
            'alternative_titles': {
              'en': 'Cowboy Bebop',
              'ja': 'カウボーイビバップ',
              'synonyms': <String>[],
            },
            'media_type': 'tv',
            'num_episodes': 26,
            'main_picture': {
              'medium': 'https://cdn.myanimelist.net/images/anime/4/19644.jpg',
              'large': 'https://cdn.myanimelist.net/images/anime/4/19644l.jpg',
            },
          },
        },
        {
          'node': {
            'id': 5,
            'title': 'Cowboy Bebop: Tengoku no Tobira',
            // Empty string, not null — MAL really does this.
            'alternative_titles': {'en': '', 'ja': '天国の扉'},
            'media_type': 'movie',
            // 0 means UNKNOWN.
            'num_episodes': 0,
            'main_picture': {'medium': 'https://cdn.myanimelist.net/m.jpg'},
          },
        },
      ],
      'paging': {'next': 'https://api.myanimelist.net/v2/anime?offset=2'},
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=UTF-8'},
);

MalClient _client(MockClient http, {String? key = 'testkey'}) => MalClient(
  httpClient: http,
  loadClientId: () async => key,
  minInterval: Duration.zero,
);

void main() {
  group('mapping', () {
    test('unwraps data[].node and maps the fields', () async {
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy bebop');

      expect(results.length, 2);
      expect(results.first.externalIds.mal, 1);
      expect(results.first.titles.romaji, 'Cowboy Bebop');
      expect(results.first.titles.native, 'カウボーイビバップ');
      expect(results.first.episodeCount, 26);
      expect(results.first.format, kFormatTv);
      expect(results.first.coverImageRef, endsWith('19644l.jpg'));
    });

    test('num_episodes 0 means UNKNOWN, not zero episodes', () async {
      // Passing 0 through would tell the missing-episodes feature the series
      // has no episodes at all, rather than leaving the count unknown as
      // AniList's null does.
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy');

      expect(results[1].episodeCount, isNull);
    });

    test('an empty english title is treated as absent', () async {
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy');

      expect(
        results[1].titles.english,
        isNull,
        reason: 'MAL sends "" not null',
      );
    });

    test('falls back to the medium picture when there is no large', () async {
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy');

      expect(results[1].coverImageRef, endsWith('m.jpg'));
    });

    test('asks for the fields MAL withholds by default', () async {
      // Without `fields` MAL returns only id/title/main_picture — no titles,
      // no media_type, no episode count.
      late Uri seen;
      await _client(
        MockClient((req) async {
          seen = req.url;
          return _searchPage();
        }),
      ).searchCandidates('cowboy');

      final fields = seen.queryParameters['fields']!;
      expect(fields, contains('alternative_titles'));
      expect(fields, contains('media_type'));
      expect(fields, contains('num_episodes'));
    });

    test('sends the client ID header', () async {
      late Map<String, String> headers;
      await _client(
        MockClient((req) async {
          headers = req.headers;
          return _searchPage();
        }),
        key: 'abc123',
      ).searchCandidates('cowboy');

      expect(headers['X-MAL-CLIENT-ID'], 'abc123');
    });

    test('caps limit at MAL\'s documented maximum of 100', () async {
      late Uri seen;
      await _client(
        MockClient((req) async {
          seen = req.url;
          return _searchPage();
        }),
      ).searchCandidates('cowboy', perPage: 500);

      expect(seen.queryParameters['limit'], '100');
    });

    test('a too-short query is a no-match, not a request', () async {
      // MAL 400s on a query under 3 characters. Sending it would knock this
      // source out of the chain for what is really an empty search.
      var called = false;
      final results = await _client(
        MockClient((_) async {
          called = true;
          return _searchPage();
        }),
      ).searchCandidates('ab');

      expect(results, isEmpty);
      expect(called, isFalse);
    });

    test('the detail endpoint is NOT wrapped in data/node', () async {
      final results = await _client(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 30230,
                'title': 'Diamond no Ace: Second Season',
                'media_type': 'tv_special',
                'num_episodes': 51,
              }),
            ),
            200,
          ),
        ),
      ).fetchByIds([30230]);

      expect(results.single.externalIds.mal, 30230);
      // tv_special is absent from MAL's published enum but real in responses.
      expect(results.single.format, kFormatSpecial);
    });

    test(
      'fetchByIds is one request per id — MAL has no batch endpoint',
      () async {
        final paths = <String>[];
        await _client(
          MockClient((req) async {
            paths.add(req.url.path);
            return http.Response.bytes(
              utf8.encode(jsonEncode({'id': 1, 'title': 'X'})),
              200,
            );
          }),
        ).fetchByIds([1, 2, 3]);

        expect(paths, ['/v2/anime/1', '/v2/anime/2', '/v2/anime/3']);
      },
    );
  });

  group('failures (error bodies probed live)', () {
    Future<MalException> failureOf(http.Response r, {String? key = 'k'}) async {
      try {
        await _client(
          MockClient((_) async => r),
          key: key,
        ).searchCandidates('cowboy');
      } on MalException catch (e) {
        return e;
      }
      fail('expected a MalException');
    }

    test('no key configured: never even asks', () async {
      var called = false;
      final e = await failureOf(_searchPage(), key: null);

      expect(e.failure, MetadataFailure.unauthorized);
      expect(called, isFalse);
    });

    test('a rejected client ID is UNAUTHORIZED, not an outage', () async {
      // Verbatim live response to a bogus key: HTTP 400, not 401.
      final e = await failureOf(
        http.Response(
          jsonEncode({'message': 'Invalid client id', 'error': 'bad_request'}),
          400,
        ),
      );

      expect(
        e.failure,
        MetadataFailure.unauthorized,
        reason: 'waiting will not fix a wrong key — the user must change it',
      );
    });

    test('403 WITH a key is throttling, not a bad key', () async {
      // MAL's docs list 403 as "DoS detected etc.". Telling the user to
      // re-check a key that is fine would send them after the wrong thing.
      final e = await failureOf(http.Response(jsonEncode({'error': ''}), 403));

      expect(e.failure, MetadataFailure.rateLimited);
    });

    test('offline is the connection', () async {
      await expectLater(
        _client(
          MockClient((_) async => throw const SocketException('offline')),
        ).searchCandidates('cowboy'),
        throwsA(
          isA<MalException>().having(
            (e) => e.failure,
            'failure',
            MetadataFailure.connection,
          ),
        ),
      );
    });
  });

  group('the provider', () {
    MalMetadataProvider provider(String? key) => MalMetadataProvider(
      _client(MockClient((_) async => _searchPage()), key: key),
      loadClientId: () async => key,
    );

    test('is unconfigured without a key, and configured with one', () async {
      expect(await provider(null).isConfigured(), isFalse);
      expect(await provider('').isConfigured(), isFalse);
      expect(await provider('abc').isConfigured(), isTrue);
    });

    test('declares that it needs a key, and is not fallback-only', () async {
      expect(provider(null).requiresClientId, isTrue);
      expect(
        provider(null).isFallbackOnly,
        isFalse,
        reason: 'reliable once configured, unlike Jikan',
      );
    });

    test('reports MAL ids into the shared mal namespace', () async {
      // Its token is its own (a separate settings row from Jikan), but the ids
      // it reports belong to the same space.
      expect(provider('k').token, isNot(provider('k').idNamespace));
      expect(provider('k').idNamespace, 'mal');
    });
  });
}
