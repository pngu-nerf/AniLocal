import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/jikan/jikan_client.dart';
import 'package:anilocal/data/metadata/jikan_metadata_provider.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Refresh asks each source by the ids stored under its ID NAMESPACE, not its
/// token. Jikan's token is `jikan` but its ids are MyAnimeList's and are stored
/// under `mal`; looked up by token, the map of "ids we hold for this source"
/// was always empty and Jikan (and the parked MAL source) could never refresh
/// a single show — silently. `MetadataProvider.idNamespace` existed for exactly
/// this and had no reader.
void main() {
  test(
    'a Jikan-identified show is re-fetched by its MAL id on refresh',
    () async {
      final dir = await Directory.systemTemp.createTemp('anilocal_ns_');
      addTearDown(() => dir.delete(recursive: true));
      final db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await File('${dir.path}/Namespace Show - 01.mkv').writeAsString('x');

      final byIdRequests = <String>[];
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (req.url.queryParameters.containsKey('q')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'mal_id': 99, 'title': 'Namespace Show'},
              ],
            }),
            200,
          );
        }
        byIdRequests.add(path);
        return http.Response(
          jsonEncode({
            'data': {'mal_id': 99, 'title': 'Namespace Show'},
          }),
          200,
        );
      });
      final jikan = JikanMetadataProvider(
        JikanClient(httpClient: mock, minInterval: Duration.zero),
      );
      LibrarySync build() => LibrarySync(
        scanner: const FileSystemFolderScanner(),
        parser: const HeuristicFilenameParser(),
        matcher: SeriesMatcher(providers: [jikan]),
        cache: db,
        art: ArtCache(
          httpClient: mock,
          directory: () async => Directory('${dir.path}/.art')..createSync(),
        ),
        skipProviders: const [],
      );

      await build().sync([dir.path]);
      final ids = await db.externalIdsBySeriesId();
      expect(
        ids.values.single.mal,
        99,
        reason: 'stored under the mal namespace',
      );
      expect(byIdRequests, isEmpty);

      final summary = await build().refreshMetadata();

      expect(byIdRequests, ['/v4/anime/99']);
      expect(summary.seriesRefreshed, 1);
    },
  );
}
