import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/library_identifier.dart';
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
  test('retries search without leading word when first search is empty '
      '(general fix for unknown site prefixes, no denylist)', () async {
    final dir = await Directory.systemTemp.createTemp('anilocal_ident_');
    addTearDown(() => dir.delete(recursive: true));
    // A prefix NOT in the parser's tiny fallback list — exercises the
    // general retry, not the AnimePahe special case.
    await File('${dir.path}/ZzzRip_Cowboy_Bebop_-_01.mkv').create();

    final searches = <String>[];
    final client = AniListClient(
      httpClient: MockClient((req) async {
        final search = (jsonDecode(req.body)['variables']['search']) as String;
        searches.add(search);
        if (search == 'Cowboy Bebop') {
          return _page([_m(1, 'Cowboy Bebop')]);
        }
        return _page(const []); // polluted query -> empty
      }),
    );

    final identifier = LibraryIdentifier(
      scanner: const FileSystemFolderScanner(),
      parser: const HeuristicFilenameParser(),
      anilist: client,
      requestSpacing: Duration.zero,
    );

    final results = await identifier.identifyFolder(dir.path);

    expect(results.single.series?.anilistId, 1);
    expect(searches, ['ZzzRip Cowboy Bebop', 'Cowboy Bebop']);
  });
}
