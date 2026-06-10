import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _page(List<Map<String, dynamic>> media) => http.Response(
  jsonEncode({
    'data': {
      'Page': {'media': media},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _m(int id, String romaji) => {
  'id': id,
  'title': {'romaji': romaji, 'english': null, 'native': null},
};

void main() {
  group('searchSeriesCandidates', () {
    test('no filter: omits format_in, parses the Page list', () async {
      late Map<String, dynamic> body;
      final client = AniListClient(
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _page([_m(1, 'A'), _m(2, 'B')]);
        }),
      );

      final result = await client.searchSeriesCandidates('frieren');

      expect(body['query'], isNot(contains('format_in')));
      expect((body['variables'] as Map).containsKey('format'), isFalse);
      expect(result.map((s) => s.anilistId), [1, 2]);
    });

    test('with filter: includes format_in + perPage variables', () async {
      late Map<String, dynamic> body;
      final client = AniListClient(
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _page([_m(1, 'A')]);
        }),
      );

      await client.searchSeriesCandidates(
        'fate',
        formatsIn: const ['TV', 'MOVIE'],
        perPage: 5,
      );

      expect(body['query'], contains('format_in'));
      expect(body['variables']['format'], ['TV', 'MOVIE']);
      expect(body['variables']['perPage'], 5);
    });

    test('empty Page returns empty list, not an error', () async {
      final client = AniListClient(
        httpClient: MockClient((req) async => _page(const [])),
      );
      expect(await client.searchSeriesCandidates('nomatch'), isEmpty);
    });
  });
}
