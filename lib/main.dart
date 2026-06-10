import 'package:flutter/material.dart';

import 'data/anilist/anilist_client.dart';
import 'data/cache/art_cache.dart';
import 'data/cache/cache_connection.dart';
import 'data/cache/cache_database.dart';
import 'data/cache/drift_library_repository.dart';
import 'data/scanner/folder_scanner.dart';
import 'data/scanner/heuristic_filename_parser.dart';
import 'data/scanner/series_matcher.dart';
import 'sync/library_sync.dart';
import 'ui/app.dart';

/// Stage 4 spike: a hardcoded library folder (settings UI is Stage 5). Must be
/// a NON-TCC-protected location (not ~/Desktop, ~/Documents, ~/Downloads).
const String kLibraryPath = '/Users/pngu/anilocal-test/library';

/// Episodic formats for the AniList candidate search (cut MUSIC false-positives).
const List<String> kEpisodicAnimeFormats = [
  'TV',
  'TV_SHORT',
  'MOVIE',
  'SPECIAL',
  'OVA',
  'ONA',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Composition root: build the cache (read path) and the sync pipeline (fill
  // path) separately. The UI is handed the repository + a scan callback only.
  final database = CacheDatabase(openCacheDatabase());
  final repository = DriftLibraryRepository(database);
  final sync = LibrarySync(
    scanner: const FileSystemFolderScanner(),
    parser: const HeuristicFilenameParser(),
    matcher: SeriesMatcher(
      anilist: AniListClient(),
      formatsIn: kEpisodicAnimeFormats,
    ),
    cache: database,
    art: ArtCache(directory: coverArtDirectory),
  );

  runApp(
    AniLocalApp(repository: repository, onScan: () => sync.sync(kLibraryPath)),
  );
}
