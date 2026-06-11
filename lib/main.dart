import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/anilist/anilist_client.dart';
import 'data/aniskip/aniskip_client.dart';
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
import 'domain/models/skip_mode.dart';
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
    // AniSkip fetched at scan time only; playback reads skips from the cache.
    aniSkip: AniSkipClient(),
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

  // Shared not-readable state, split by KIND so each surfaces the right
  // recovery: denied -> Settings/Files-and-Folders banner; missing (unplugged
  // drive / offline NAS) -> "reconnect" banner, no Settings. A label lives in
  // at most one set; becoming accessible clears it from both. One source of
  // truth so the add-dialog and the ambient banners can't disagree.
  final accessIssues = ValueNotifier<List<String>>(const []);
  final missingFolders = ValueNotifier<List<String>>(const []);
  void applyAccess(FolderAccessResult r) {
    final label = r.categoryLabel;
    if (label == null) return; // not a TCC category / volume
    final denied = {...accessIssues.value}..remove(label);
    final missing = {...missingFolders.value}..remove(label);
    if (r.isDenied) denied.add(label);
    if (r.isMissing) missing.add(label);
    accessIssues.value = denied.toList()..sort();
    missingFolders.value = missing.toList()..sort();
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
  const autoPlayNextKey = 'autoplay_next';
  const skipModeKey = 'skip_mode';

  runApp(
    AniLocalApp(
      repository: repository,
      fixMatch: fixMatch,
      // DriftLibraryRepository implements WatchStateRepository +
      // SourceSelectionRepository + WatchOrderRepository too (read + the
      // per-episode-identity writes).
      watchState: repository,
      sourceSelection: repository,
      watchOrder: repository,
      onScan: scan,
      onRefreshMetadata: sync.refreshMetadata,
      onAddFolder: addFolder,
      accessIssues: accessIssues,
      missingFolders: missingFolders,
      onOpenAccessSettings: openPrivacyFilesAndFoldersSettings,
      loadContinueCollapsed: () async =>
          await database.getSetting(continueCollapsedKey) == 'true',
      setContinueCollapsed: (collapsed) =>
          database.setSetting(continueCollapsedKey, '$collapsed'),
      // Auto-play next defaults ON: only an explicit 'false' disables it.
      loadAutoPlayNext: () async =>
          await database.getSetting(autoPlayNextKey) != 'false',
      setAutoPlayNext: (enabled) =>
          database.setSetting(autoPlayNextKey, '$enabled'),
      // Skip mode defaults to "button" (SkipMode.fromToken maps null -> button).
      loadSkipMode: () async =>
          SkipMode.fromToken(await database.getSetting(skipModeKey)),
      setSkipMode: (mode) => database.setSetting(skipModeKey, mode.token),
    ),
  );
}
