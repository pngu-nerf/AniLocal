import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal valid AniList response so the mapper succeeds.
http.Response _okMedia() => http.Response(
  jsonEncode({
    'data': {
      'Media': {
        'id': 1,
        'title': {'romaji': 'X', 'english': null, 'native': null},
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

        await client.fetchSeriesByTitle('frieren');

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

      await client.fetchSeriesByTitle('fate', formatsIn: const ['TV', 'MOVIE']);

      expect(body['query'], contains('format_in'));
      expect(body['variables']['format'], ['TV', 'MOVIE']);
    });

    test('throws AniListException on non-200', () async {
      final client = AniListClient(
        httpClient: MockClient((req) async => http.Response('boom', 500)),
      );

      expect(
        () => client.fetchSeriesByTitle('frieren'),
        throwsA(isA<AniListException>()),
      );
    });
  });
}
