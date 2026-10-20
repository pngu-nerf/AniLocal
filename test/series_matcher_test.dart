import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/metadata/anilist_metadata_provider.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/graphql_request.dart';

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
  group('SeriesMatcher', () {
    test('retries without leading word when first search is empty', () async {
      final searches = <String>[];
      final matcher = SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient((req) async {
                final search = (graphqlVariables(req)['search']) as String;
                searches.add(search);
                if (search == 'Cowboy Bebop') {
                  return _page([_m(1, 'Cowboy Bebop')]);
                }
                return _page(const []); // polluted query -> empty
              }),
            ),
          ),
        ],
      );

      final result = await matcher.match('ZzzRip Cowboy Bebop');

      expect(result.series?.seriesId, 1);
      expect(searches, ['ZzzRip Cowboy Bebop', 'Cowboy Bebop']);
    });

    test('then retries without the trailing word', () async {
      final searches = <String>[];
      final matcher = SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient((req) async {
                final search = (graphqlVariables(req)['search']) as String;
                searches.add(search);
                if (search == 'Cowboy Bebop') {
                  return _page([_m(1, 'Cowboy Bebop')]);
                }
                return _page(const []);
              }),
            ),
          ),
        ],
      );

      final result = await matcher.match('Cowboy Bebop Remaster');

      expect(result.series?.seriesId, 1);
      expect(searches, [
        'Cowboy Bebop Remaster',
        'Bebop Remaster',
        'Cowboy Bebop',
      ]);
    });

    test('a one-word title that finds nothing is asked exactly once', () async {
      var calls = 0;
      final matcher = SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient((req) async {
                calls++;
                return _page(const []);
              }),
            ),
          ),
        ],
      );

      final result = await matcher.match('Zzzunknown');

      expect(result.series, isNull);
      expect(calls, 1);
    });

    test('fallbackQueries: two words give each word once, one word itself', () {
      expect(SeriesMatcher.fallbackQueries('Cowboy Bebop'), [
        'Cowboy Bebop',
        'Bebop',
        'Cowboy',
      ]);
      expect(SeriesMatcher.fallbackQueries('Bebop'), ['Bebop']);
    });

    test('returns no match when candidates score below the floor', () async {
      final matcher = SeriesMatcher(
        providers: [
          AniListMetadataProvider(
            AniListClient(
              httpClient: MockClient(
                (req) async => _page([_m(1, 'Completely Different Show')]),
              ),
            ),
          ),
        ],
      );

      final result = await matcher.match('zzz nonsense qux');
      expect(result.series, isNull);
    });
  });
}
