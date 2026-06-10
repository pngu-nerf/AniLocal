import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
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
  test('retries without leading word when first search is empty', () async {
    final searches = <String>[];
    final matcher = SeriesMatcher(
      anilist: AniListClient(
        httpClient: MockClient((req) async {
          final search =
              (jsonDecode(req.body)['variables']['search']) as String;
          searches.add(search);
          if (search == 'Cowboy Bebop') return _page([_m(1, 'Cowboy Bebop')]);
          return _page(const []); // polluted query -> empty
        }),
      ),
    );

    final result = await matcher.match('ZzzRip Cowboy Bebop');

    expect(result.series?.anilistId, 1);
    expect(searches, ['ZzzRip Cowboy Bebop', 'Cowboy Bebop']);
  });

  test('returns no match when candidates score below the floor', () async {
    final matcher = SeriesMatcher(
      anilist: AniListClient(
        httpClient: MockClient(
          (req) async => _page([_m(1, 'Completely Different Show')]),
        ),
      ),
    );

    final result = await matcher.match('zzz nonsense qux');
    expect(result.series, isNull);
  });
}
