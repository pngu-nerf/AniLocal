import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal valid AniList response so the mapper succeeds.
http.Response _okMedia() => http.Response(
  jsonEncode({
    'data': {
      'Page': {
        'media': [
          {
            'id': 1,
            'title': {'romaji': 'X', 'english': null, 'native': null},
          },
        ],
      },
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('AniListClient request shape', () {
    test(
      'no filter: omits format_in entirely (AniList 500s on null)',
      () async {
        late Map<String, dynamic> body;
        final client = AniListClient(
          httpClient: MockClient((req) async {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return _okMedia();
          }),
        );

        await client.searchSeriesCandidates('frieren');

        expect(body['query'], isNot(contains('format_in')));
        expect((body['variables'] as Map).containsKey('format'), isFalse);
      },
    );

    test('with filter: includes format_in and the format variable', () async {
      late Map<String, dynamic> body;
      final client = AniListClient(
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _okMedia();
        }),
      );

      await client.searchSeriesCandidates(
        'fate',
        formatsIn: const ['TV', 'MOVIE'],
      );

      expect(body['query'], contains('format_in'));
      expect(body['variables']['format'], ['TV', 'MOVIE']);
    });

    test('throws AniListException on non-200', () async {
      final client = AniListClient(
        httpClient: MockClient((req) async => http.Response('boom', 500)),
      );

      expect(
        () => client.searchSeriesCandidates('frieren'),
        throwsA(isA<AniListException>()),
      );
    });
  });

  // The failure kind is what the UI renders, so each shape is pinned. The
  // headline case is AniList's REAL outage response: a 403 that carries a
  // well-formed GraphQL error envelope. Every prior outage test used a
  // plain-text body, so nothing proved the status check runs before the body
  // is read — i.e. that this can't be mistaken for "no results".
  group('AniListClient failure attribution', () {
    /// AniList's verbatim outage response (observed 2026-09-08).
    http.Response apiDisabled() => http.Response(
      jsonEncode({
        'errors': [
          {
            'message':
                'The AniList API has been temporarily disabled due to '
                'severe stability issues.',
            'status': 403,
          },
        ],
        'data': null,
      }),
      403,
      headers: {'content-type': 'application/json'},
    );

    Future<AniListException> failureOf(http.Response response) async {
      final client = AniListClient(
        httpClient: MockClient((_) async => response),
      );
      try {
        await client.searchSeriesCandidates('frieren');
      } on AniListException catch (e) {
        return e;
      }
      fail('expected an AniListException');
    }

    test(
      '403 with AniList\'s GraphQL body is AniList\'s end, not ours',
      () async {
        final e = await failureOf(apiDisabled());

        expect(e.failure, MetadataFailure.service);
        // AniList's own words survive into the message, so a log says WHY.
        expect(e.message, contains('temporarily disabled'));
      },
    );

    test(
      'a disabled API never degrades into an empty candidate list',
      () async {
        final client = AniListClient(
          httpClient: MockClient((_) async => apiDisabled()),
        );

        // The 403 body has `data: null`, the same shape a genuine no-match has.
        // It must throw, NOT return [] — a silent [] would flip files to
        // confirmed-unmatched and they'd never be retried.
        await expectLater(
          client.searchSeriesCandidates('frieren'),
          throwsA(isA<AniListException>()),
        );
      },
    );

    test('4xx with a non-AniList body blames the network path', () async {
      // A Cloudflare/proxy/captive-portal interstitial: HTML, not GraphQL.
      final e = await failureOf(
        http.Response('<html>Access denied</html>', 403),
      );

      expect(e.failure, MetadataFailure.blocked);
    });

    test('5xx is AniList\'s end whoever rendered the page', () async {
      final e = await failureOf(http.Response('<html>Bad gateway</html>', 502));

      expect(e.failure, MetadataFailure.service);
    });

    test('429 is reported as rate limiting', () async {
      final e = await failureOf(http.Response('slow down', 429));

      expect(e.failure, MetadataFailure.rateLimited);
    });

    test('a transport failure is the user\'s connection', () async {
      final client = AniListClient(
        httpClient: MockClient(
          (_) async => throw const SocketException('Network is unreachable'),
        ),
      );

      await expectLater(
        client.searchSeriesCandidates('frieren'),
        throwsA(
          isA<AniListException>().having(
            (e) => e.failure,
            'failure',
            MetadataFailure.connection,
          ),
        ),
      );
    });

    test(
      'a 200 carrying HTML throws AniListException, not FormatException',
      () async {
        // Guards the unguarded-cast hole: a bare FormatException would escape
        // every `on AniListException` handler in LibrarySync, aborting the scan
        // and skipping the cache-preserving unreachable guard.
        final e = await failureOf(http.Response('<html>nope</html>', 200));

        expect(e.failure, MetadataFailure.service);
        expect(e.message, contains('Malformed'));
      },
    );

    test('a 200 carrying GraphQL errors still throws', () async {
      final e = await failureOf(
        http.Response(
          jsonEncode({
            'errors': [
              {'message': 'Too Many Requests'},
            ],
            'data': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(e.failure, MetadataFailure.service);
    });
  });
}
