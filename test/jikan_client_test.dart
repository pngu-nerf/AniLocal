import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/crossmap/cross_map_store.dart';
import 'package:anilocal/data/jikan/jikan_client.dart';
import 'package:anilocal/data/metadata/jikan_metadata_provider.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/series_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fixtures follow the real /v4 shape, captured from api.jikan.moe during this
/// work. NOTE: Jikan was fully 504ing by the time these were written, so the
/// shape could not be re-validated live afterwards — unlike the Kitsu ones.
/// That unreliability is precisely why this source is fallback-only.
http.Response _searchPage() => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'data': [
        {
          'mal_id': 1,
          'title': 'Cowboy Bebop',
          'title_english': 'Cowboy Bebop',
          'title_japanese': 'カウボーイビバップ',
          'type': 'TV',
          'episodes': 26,
          'images': {
            'jpg': {
              'image_url':
                  'https://cdn.myanimelist.net/images/anime/4/19644.jpg',
              'large_image_url':
                  'https://cdn.myanimelist.net/images/anime/4/19644l.jpg',
            },
          },
        },
        {
          'mal_id': 5,
          'title': 'Cowboy Bebop: Tengoku no Tobira',
          'title_english': null,
          'title_japanese': 'カウボーイビバップ 天国の扉',
          'type': 'Movie',
          'episodes': 1,
          'images': {'jpg': {}},
        },
      ],
    }),
  ),
  200,
  // No charset — exactly what Jikan sends, and the latin1 trap it implies.
  headers: {'content-type': 'application/json'},
);

JikanClient _client(MockClient http) =>
    JikanClient(httpClient: http, minInterval: Duration.zero);

void main() {
  group('mapping', () {
    test('maps titles, format, episodes and image', () async {
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy bebop');

      expect(results.length, 2);
      expect(results.first.titles.romaji, 'Cowboy Bebop');
      expect(results.first.titles.native, 'カウボーイビバップ');
      expect(results.first.episodeCount, 26);
      expect(results.first.coverImageRef, contains('19644l.jpg'));
    });

    test("MAL's 'Movie' becomes the shared MOVIE token", () async {
      final results = await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy');

      expect(results[0].format, kFormatTv);
      expect(results[1].format, kFormatMovie);
    });

    test(
      'falls back through image sizes when the large one is absent',
      () async {
        final results = await _client(
          MockClient((_) async => _searchPage()),
        ).searchCandidates('cowboy');

        expect(results[1].coverImageRef, isNull, reason: 'jpg map was empty');
      },
    );

    test('reports the MAL id and nothing it does not know', () async {
      final ids = (await _client(
        MockClient((_) async => _searchPage()),
      ).searchCandidates('cowboy')).first.externalIds;

      expect(ids.mal, 1);
      expect(ids.anilist, isNull, reason: 'Jikan publishes only MAL ids');
    });

    test(
      'fetchByIds issues ONE request per id — there is no batch endpoint',
      () async {
        final paths = <String>[];
        await _client(
          MockClient((req) async {
            paths.add(req.url.path);
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'data': {'mal_id': 1, 'title': 'X', 'type': 'TV'},
                }),
              ),
              200,
            );
          }),
        ).fetchByIds([1, 5, 9]);

        expect(paths, ['/v4/anime/1', '/v4/anime/5', '/v4/anime/9']);
      },
    );
  });

  group('the cross-map closes Jikan\'s id gap', () {
    test('a MAL-only answer gains its AniList id', () async {
      // Without this a Jikan-identified show would mint a fresh identity even
      // though AniList already names it.
      final dir = await Directory.systemTemp.createTemp('anilocal_jikan_');
      addTearDown(() => dir.delete(recursive: true));

      final provider = JikanMetadataProvider(
        _client(MockClient((_) async => _searchPage())),
        crossMap: CrossMapStore(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode([
                {'anilist_id': 21, 'mal_id': 1},
              ]),
              200,
            ),
          ),
          directory: () async => dir,
        ),
      );

      final ids = (await provider.searchCandidates('cowboy')).first.externalIds;

      expect(ids.mal, 1);
      expect(ids.anilist, 21, reason: 'supplied by the cross-map');
    });

    test('without a cross-map the answer still works, just MAL-only', () async {
      final provider = JikanMetadataProvider(
        _client(MockClient((_) async => _searchPage())),
      );

      final ids = (await provider.searchCandidates('cowboy')).first.externalIds;

      expect(ids.mal, 1);
      expect(ids.anilist, isNull);
    });

    test('is declared fallback-only', () async {
      expect(
        JikanMetadataProvider(
          _client(MockClient((_) async => _searchPage())),
        ).isFallbackOnly,
        isTrue,
      );
    });
  });

  group('failures', () {
    test('a 504 from Jikan\'s gateway is THEIR end, not the user\'s', () async {
      // Jikan's characteristic failure. MAL itself is usually fine underneath,
      // so blaming the user's connection would send them debugging nothing.
      try {
        await _client(
          MockClient((_) async => http.Response('gateway timeout', 504)),
        ).searchCandidates('x');
        fail('expected a JikanException');
      } on JikanException catch (e) {
        expect(e.failure, MetadataFailure.service);
      }
    });

    test("Jikan's REAL outage body is parsed and blamed correctly", () async {
      // Captured verbatim from api.jikan.moe during this work. Note what it
      // says: MAL is refusing JIKAN, while MAL itself answers browsers fine —
      // so the failure is between Jikan and MAL, outside anyone's control here,
      // and `service` is the honest attribution.
      try {
        await _client(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'status': 504,
                'type': 'HttpException',
                'message':
                    'Jikan failed to connect to MyAnimeList. MyAnimeList may '
                    'be down/unavailable or refuses to connect',
                'error': null,
              }),
              504,
            ),
          ),
        ).searchCandidates('x');
        fail('expected a JikanException');
      } on JikanException catch (e) {
        expect(e.failure, MetadataFailure.service);
        expect(
          e.message,
          contains('refuses to connect'),
          reason:
              "Jikan's own words survive into the message, so a log says why",
        );
      }
    });

    test('offline is the connection', () async {
      await expectLater(
        _client(
          MockClient((_) async => throw const SocketException('offline')),
        ).searchCandidates('x'),
        throwsA(
          isA<JikanException>().having(
            (e) => e.failure,
            'failure',
            MetadataFailure.connection,
          ),
        ),
      );
    });

    test(
      'requests are spaced so the 3/second limiter is not tripped',
      () async {
        var calls = 0;
        final client = JikanClient(
          httpClient: MockClient((_) async {
            calls++;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'data': {'mal_id': 1, 'title': 'X'},
                }),
              ),
              200,
            );
          }),
          minInterval: const Duration(milliseconds: 60),
        );

        final started = DateTime.now();
        await client.fetchByIds([1, 2, 3]);
        final elapsed = DateTime.now().difference(started);

        expect(calls, 3);
        expect(
          elapsed.inMilliseconds,
          greaterThanOrEqualTo(120),
          reason: 'two gaps of at least the minimum interval',
        );
      },
    );
  });
}
