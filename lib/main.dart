import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/anilist/anilist_client.dart';
import 'data/cache/art_cache.dart';
import 'data/cache/cache_connection.dart';
import 'data/cache/cache_database.dart';
import 'data/cache/drift_library_repository.dart';
import 'data/folders/file_selector_folder_picker.dart';
import 'data/folders/folder_access.dart';
import 'data/folders/tcc_folder_access.dart';
import 'data/scanner/folder_scanner.dart';
import 'data/scanner/heuristic_filename_parser.dart';
import 'data/scanner/series_matcher.dart';
import 'domain/models/sync_summary.dart';
import 'sync/fix_match_service.dart';
import 'sync/library_sync.dart';
import 'ui/app.dart';

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
  // Initialize libmpv before any Player is constructed (library playback).
  MediaKit.ensureInitialized();

  // Composition root. Read path (cache) and fill path (sync) are built
  // separately; the UI gets the repository + scan/add-folder callbacks only.
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
  // Fix-match: the ONLY writer of overrides (LibrarySync can't reach it).
  final fixMatch = FixMatchService(
    anilist: AniListClient(),
    art: ArtCache(directory: coverArtDirectory),
    cache: database,
    formatsIn: kEpisodicAnimeFormats,
  );
  const FolderPicker picker = FileSelectorFolderPicker();
  final FolderAccess folderAccess = TccFolderAccess();

  // Shared denied-state: one source of truth for both the add-dialog and the
  // ambient banner, so they can't disagree. Holds the denied category labels.
  final accessIssues = ValueNotifier<List<String>>(const []);
  void applyAccess(FolderAccessResult r) {
    if (r.categoryLabel == null) return; // not a TCC category
    final set = {...accessIssues.value};
    r.isDenied ? set.add(r.categoryLabel!) : set.remove(r.categoryLabel!);
    accessIssues.value = set.toList()..sort();
  }

  // Folders are user-picked via the native panel — there is NO hardcoded path.
  // Adding a folder under a TCC category provokes the folder-wide prompt (so
  // the picker stops greying siblings); a denial surfaces via [deniedLabel] +
  // the shared accessIssues. The folder is still recorded and scans via its own
  // inferred-consent grant (additive — a category deny never regresses it).
  Future<({bool added, String? deniedLabel})> addFolder() async {
    final token = await picker.pickFolder();
    if (token == null) return (added: false, deniedLabel: null);
    await repository.addFolder(token.path);
    final result = await folderAccess.ensureAccess(token.path);
    applyAccess(result);
    return (
      added: true,
      deniedLabel: result.isDenied ? result.categoryLabel : null,
    );
  }

  Future<SyncSummary> scan() async {
    final folders = await repository.watchedFolders();
    // Confirm/upgrade folder-wide access per category (additive — does NOT gate
    // the scan; the scanner still reads each folder via whatever grant it has).
    for (final f in folders) {
      applyAccess(await folderAccess.ensureAccess(f.path));
    }
    return sync.sync([for (final f in folders) f.path]);
  }

  const continueCollapsedKey = 'continue_watching_collapsed';

  runApp(
    AniLocalApp(
      repository: repository,
      fixMatch: fixMatch,
      // DriftLibraryRepository implements WatchStateRepository +
      // SourceSelectionRepository too (read + per-episode-identity writes).
      watchState: repository,
      sourceSelection: repository,
      onScan: scan,
      onAddFolder: addFolder,
      accessIssues: accessIssues,
      onOpenAccessSettings: openPrivacyFilesAndFoldersSettings,
      loadContinueCollapsed: () async =>
          await database.getSetting(continueCollapsedKey) == 'true',
      setContinueCollapsed: (collapsed) =>
          database.setSetting(continueCollapsedKey, '$collapsed'),
    ),
  );
}
