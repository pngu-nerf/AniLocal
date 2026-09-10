import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'data/anilist/anilist_client.dart';
import 'data/aniskip/aniskip_client.dart';
import 'data/cache/art_cache.dart';
import 'data/cache/cache_connection.dart';
import 'data/cache/cache_database.dart';
import 'data/cache/drift_library_repository.dart';
import 'data/cache/drift_settings_repository.dart';
import 'data/crossmap/cross_map_store.dart';
import 'data/jikan/jikan_client.dart';
import 'data/mal/mal_client.dart';
import 'data/kitsu/kitsu_client.dart';
import 'data/metadata/anilist_metadata_provider.dart';
import 'data/metadata/jikan_metadata_provider.dart';
import 'data/metadata/kitsu_metadata_provider.dart';
import 'data/metadata/mal_metadata_provider.dart';
import 'data/skip/aniskip_skip_provider.dart';
import 'data/skip/chapters_skip_provider.dart';
import 'data/skip/skip_provider.dart';
import 'data/metadata/metadata_provider.dart';
import 'data/folders/file_selector_folder_picker.dart';
import 'data/folders/folder_access.dart';
import 'data/folders/tcc_folder_access.dart';
import 'data/folders/volume_resolver.dart';
import 'data/scanner/folder_scanner.dart';
import 'data/scanner/heuristic_filename_parser.dart';
import 'data/scanner/series_matcher.dart';
import 'domain/models/external_ids.dart';
import 'domain/models/source_descriptor.dart';
import 'domain/models/sync_summary.dart';
import 'playback/playback_controller.dart';
import 'sync/fix_match_service.dart';
import 'sync/library_sync.dart';
import 'ui/app.dart';
import 'ui/window_chrome.dart';

/// Episodic formats for the AniList candidate search (cut MUSIC false-positives).
const List<String> kEpisodicAnimeFormats = [
  'TV',
  'TV_SHORT',
  'MOVIE',
  'SPECIAL',
  'OVA',
  'ONA',
];

/// Whether the MyAnimeList source appears in the app at all.
///
/// OFF on purpose, not unfinished. MAL is the only source that needs a
/// credential, and getting one means each user registering their own
/// application with MyAnimeList and accepting its developer agreement — a real
/// onboarding wall for a "point at a folder and go" product, in exchange for
/// almost nothing: AniList and Kitsu already identify shows, and the MAL id
/// AniSkip needs already arrives via AniList and the cross-map.
///
/// Everything behind this flag is complete and covered by tests; flip it to
/// true and MAL appears in Settings > Metadata, inert until a key is pasted.
/// `docs/myanimelist-registration.md` records the registration flow so the
/// decision can be revisited without re-deriving it.
///
/// It is not only MAL's flag in effect: MAL is currently the ONLY source that
/// sets `requiresClientId`, so hiding it is what makes the whole client-ID
/// subsystem — the key dialog, the per-source key storage, `setupUrl` /
/// `setupInstructions`, `MetadataFailure.unauthorized` — unreachable at
/// runtime. That code is retained for the same reason MAL is, and Anime Skip
/// (also parked, also account-gated) would light up the identical path. See
/// `docs/multi-source-plan.md` for the parked set as a whole.
const bool kShipMyAnimeListSource = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv before any Player is constructed (library playback).
  MediaKit.ensureInitialized();
  // Start listening for native window-state callbacks (fullscreen enter/exit).
  // Installed here, once, so the signal is live before any screen reads it —
  // WindowChrome.fullscreen is the single source of truth the theater derives
  // its layout AND its keyboard-focus reclaim from.
  WindowChrome.ensureInitialized();

  // Composition root. Read path (cache) and fill path (sync) are built
  // separately; the UI gets the repository + scan/add-folder callbacks only.
  final database = CacheDatabase(openCacheDatabase());
  // One resolver, shared by the read path and the fill path: it follows a
  // library volume across remounts (different /Volumes name) by its UUID, so
  // file identity stays stable. Sharing the instance also shares its mount
  // memoization. Internal-disk folders never touch it (their path is stable).
  final VolumeResolver volumeResolver = DiskutilVolumeResolver();
  final repository = DriftLibraryRepository(database, resolver: volumeResolver);
  // ONE cross-map instance: shared by the AniSkip id backfill and by Jikan's
  // MAL -> AniList enrichment, so the 5.8MB source is fetched and parsed once.
  final crossMap = CrossMapStore(directory: derivedDataDirectory);
  // ALL settings live behind one injected object (was ~20 threaded functions).
  // Adding a setting now touches SettingsRepository + its impl + the reader.
  // Built BEFORE the fill path because the matcher reads the user's metadata
  // source order from it.
  final settings = DriftSettingsRepository(
    database,
    showPreferences: repository,
  );
  // Wired back after settings exists: DriftSettingsRepository is built FROM the
  // library repository (it delegates show-preferences to it), so the minimum-
  // skip floor cannot be a constructor argument on either.
  repository.loadMinSkipLength = settings.loadMinSkipLength;
  // Read fresh on every use, so pasting a key in Settings works immediately and
  // clearing one disables the source immediately.
  Future<String?> malClientId() =>
      settings.loadSourceClientId(kMyAnimeListProvider);
  // ONE ordered source list, shared by the scan and by fix-match so the two
  // can never disagree about which source is preferred. Today it holds a single
  // provider; adding one is appending to this list.
  // Built-in order; the user can reorder or disable any of them in
  // Settings > Metadata, and that order is read fresh on every lookup.
  final metadataProviders = <MetadataProvider>[
    AniListMetadataProvider(AniListClient(), formatsIn: kEpisodicAnimeFormats),
    // Keyless, and the only rich source still answering while AniList's API is
    // disabled. Slower, which the two-phase scan hides: placeholders paint from
    // phase 1 before any lookup runs.
    KitsuMetadataProvider(KitsuClient()),
    // MAL's data with no key — but through a volunteer-run proxy measured at
    // roughly 30% availability, so it is FALLBACK-ONLY and sorts last however
    // the user orders the list. The cross-map supplies the AniList id Jikan
    // doesn't publish, so its answers land on the same identities as everyone
    // else's.
    JikanMetadataProvider(JikanClient(), crossMap: crossMap),
    // MyAnimeList is BUILT AND TESTED but deliberately NOT SHIPPED — see
    // `docs/myanimelist-registration.md` for why, and for the registration flow
    // if it comes back. Flipping [kShipMyAnimeListSource] is the whole
    // re-enable: the client, the adapter, the key storage, the key dialog and
    // their tests all stay in the tree and keep running, so none of it rots.
    if (kShipMyAnimeListSource)
      MalMetadataProvider(
        MalClient(loadClientId: () => malClientId()),
        loadClientId: malClientId,
      ),
  ];
  // Built-in skip order: the FILE'S OWN chapters first, then AniSkip.
  //
  // Chapters lead because of where their data comes from: a chapter mark was
  // authored against the exact encode sitting on disk, while AniSkip is
  // crowd-sourced timings submitted against whatever release the submitter had.
  // When those differ, the local one is right by construction.
  //
  // Measured, not assumed. On the reference library, cross-checking flagged
  // Cyberpunk: Edgerunners as disagreeing on all 9 episodes; AniSkip put the
  // opening at 76.2s and the opening actually starts at 71s. Its window is
  // exactly 90s, so the 5.2s late start pushes the END 5.2s past the opening
  // and INTO the episode — the one skip error a viewer cannot undo. Sakamoto
  // desu ga? showed the same total disagreement, and six more shows disagreed
  // on 13-36% of episodes.
  //
  // This costs nothing in coverage: only ~37% of files carry chapters, and a
  // source with no data falls through silently, so AniSkip still answers
  // everything else. It complements AniSkip rather than replacing it — the
  // order just decides who wins where BOTH have an answer.
  //
  // The residual risk runs the other way: a chapters window is INFERRED from a
  // duration band, so a non-theme span of about 90s could in principle be
  // picked, where AniSkip's answer is human-curated. `inferSkipsFromChapters`
  // declines rather than guesses, and cross-checking is the backstop — a bogus
  // chapters window disagrees with AniSkip and is then never auto-skipped.
  final skipProviders = <SkipProvider>[
    const ChaptersSkipProvider(),
    AniSkipSkipProvider(AniSkipClient()),
  ];
  final sync = LibrarySync(
    scanner: const FileSystemFolderScanner(),
    parser: const HeuristicFilenameParser(),
    matcher: SeriesMatcher(
      providers: metadataProviders,
      // Read fresh per scan, so reordering sources in Settings takes effect
      // without a restart.
      loadOrder: settings.loadMetadataSourceOrder,
    ),
    cache: database,
    art: ArtCache(directory: coverArtDirectory),
    // ONE ordered skip-source list, mirroring the metadata one. Fetched at
    // scan time only; playback still reads skips from the cache and makes no
    // network call. Chapters, Anime Skip and fingerprinting append here.
    skipProviders: skipProviders,
    loadSkipOrder: settings.loadSkipSourceOrder,
    loadCorroborateSkips: settings.loadCorroborateSkips,
    // Fills a MAL id AniList didn't supply, so auto-skip survives an AniList
    // outage. Fetched lazily and only when something is actually missing.
    crossMap: crossMap,
    resolver: volumeResolver,
  );
  // Fix-match: the ONLY writer of overrides (LibrarySync can't reach it).
  final fixMatch = FixMatchService(
    providers: metadataProviders,
    art: ArtCache(directory: coverArtDirectory),
    cache: database,
    loadOrder: settings.loadMetadataSourceOrder,
  );
  // Descriptors for the Settings > Metadata list, derived from the ONE provider
  // list so the two can't list different sources. `configured` is a snapshot
  // for first paint; the panel re-derives it live from the stored key, so
  // pasting one takes effect without a restart.
  final metadataSourceDescriptors = [
    for (final p in metadataProviders)
      SourceDescriptor(
        token: p.token,
        displayName: p.displayName,
        requiresClientId: p.requiresClientId,
        fallbackOnly: p.isFallbackOnly,
        setupHint: p.requiresClientId
            ? 'Needs a free client ID from your own ${p.displayName} account'
            : null,
        setupUrl: p.setupUrl,
        setupInstructions: p.setupInstructions,
      ),
  ];

  const FolderPicker picker = FileSelectorFolderPicker();
  final FolderAccess folderAccess = TccFolderAccess();

  // Shared not-readable state, split by KIND so each surfaces the right
  // recovery: denied -> Settings/Files-and-Folders banner; missing (unplugged
  // drive / offline NAS) -> "reconnect" banner, no Settings. A label lives in
  // at most one set; becoming accessible clears it from both. One source of
  // truth so the add-dialog and the ambient banners can't disagree.
  final accessIssues = ValueNotifier<List<String>>(const []);
  final missingFolders = ValueNotifier<List<String>>(const []);
  // Missing folder PATHS (vs the human labels above): lets the library grey
  // out shows sourced only from these. Populated by [scan] from the same
  // ensureAccess results that drive the reconnect banner.
  final missingFolderPaths = ValueNotifier<Set<String>>(const {});
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

  Future<SyncSummary> scan(void Function() onDiscovered) async {
    // Folder ROWS (not just paths) carry each folder's volume binding, so we can
    // resolve its CURRENT mount before checking access.
    final folders = await database.allFolderRows();
    // Confirm/upgrade folder-wide access per category (additive — does NOT gate
    // the scan; the scanner still reads each folder via whatever grant it has).
    // Check on the CURRENT mount so a volume that remounted under a NEW name is
    // not mistaken for missing; a truly-unmounted volume (resolves to null)
    // reports missing via its stable path. Same pass records which folder PATHS
    // are currently missing so the UI can grey out shows sourced only there —
    // replaced wholesale each scan, so a replugged folder clears automatically.
    final missingPaths = <String>{};
    for (final f in folders) {
      final current = await resolveFolderPath(
        storedPath: f.path,
        volumeId: f.volumeId,
        volumeSubpath: f.volumeSubpath,
        resolver: volumeResolver,
      );
      final result = await folderAccess.ensureAccess(current ?? f.path);
      applyAccess(result);
      if (current == null || result.isMissing) missingPaths.add(f.path);
    }
    missingFolderPaths.value = missingPaths;
    return sync.sync([
      for (final f in folders) f.path,
    ], onDiscovered: onDiscovered);
  }

  // The playback engine is APP-LIFETIME: built once here, injected, and kept
  // alive across navigation. Leaving the theater now stops it instead of
  // destroying it, so libmpv is constructed once per app run rather than once
  // per visit — see PlaybackController's doc and
  // docs/player-architecture-research.md. `repository` is the WatchOrder
  // resolver (the single "what's next" source) the advance path routes through.
  final playback = PlaybackController(resolver: repository);

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
      // DriftLibraryRepository also implements MissingEpisodesRepository (the
      // sacred hidden-episode store; keyed by episode identity like watch-state).
      missing: repository,
      // …and ShowPreferencesRepository (per-show cover/next-episode prefs).
      showPreferences: repository,
      settings: settings,
      // Descriptors for the Settings > Metadata list, derived from the ONE
      // provider list so the two can't list different sources.
      metadataSources: metadataSourceDescriptors,
      skipSources: [
        for (final p in skipProviders)
          SourceDescriptor(
            token: p.token,
            displayName: p.displayName,
            requiresClientId: p.requiresClientId,
            setupUrl: p.setupUrl,
            setupInstructions: p.setupInstructions,
            setupHint: p.requiresClientId
                ? 'Needs a free client ID from your own ${p.displayName} '
                      'account'
                : null,
          ),
      ],
      playback: playback,
      onScan: scan,
      onRefreshMetadata: sync.refreshMetadata,
      onAddFolder: addFolder,
      accessIssues: accessIssues,
      missingFolders: missingFolders,
      missingFolderPaths: missingFolderPaths,
      onOpenAccessSettings: openPrivacyFilesAndFoldersSettings,
    ),
  );
}
