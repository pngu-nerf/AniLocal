import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/anilist/anilist_client.dart';
import 'data/aniskip/aniskip_client.dart';
import 'data/cache/art_cache.dart';
import 'data/cache/cache_connection.dart';
import 'data/cache/cache_database.dart';
import 'data/cache/drift_library_repository.dart';
import 'data/cache/drift_settings_repository.dart';
import 'data/cache/skip_view_source.dart';
import 'data/crossmap/cross_map_store.dart';
import 'data/folders/file_selector_folder_picker.dart';
import 'data/folders/folder_access.dart';
import 'data/folders/tcc_folder_access.dart';
import 'data/folders/volume_resolver.dart';
import 'data/jikan/jikan_client.dart';
import 'data/kitsu/kitsu_client.dart';
import 'data/mal/mal_client.dart';
import 'data/metadata/anilist_metadata_provider.dart';
import 'data/metadata/jikan_metadata_provider.dart';
import 'data/metadata/kitsu_metadata_provider.dart';
import 'data/metadata/mal_metadata_provider.dart';
import 'data/metadata/metadata_provider.dart';
import 'data/scanner/folder_scanner.dart';
import 'data/scanner/heuristic_filename_parser.dart';
import 'data/scanner/series_matcher.dart';
import 'data/skip/aniskip_skip_provider.dart';
import 'data/skip/chapters_skip_provider.dart';
import 'data/skip/skip_provider.dart';
import 'data/timeout_client.dart';
import 'data/user_agent.dart';
import 'diagnostics/app_log.dart';
import 'diagnostics/diagnostics.dart';
import 'domain/models/external_ids.dart';
import 'domain/models/folder_refused.dart';
import 'domain/models/source_descriptor.dart';
import 'domain/models/source_preference.dart';
import 'domain/models/sync_control.dart';
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

Future<void> main() async {
  // Failures leave a trail. Installed FIRST, before the binding, so an error
  // during binding initialisation is captured too. Before this there was no error hook and no log of
  // any kind: an uncaught async error in a release build went to the unified
  // system log where no user looks, and an uncaught build error drew a blank
  // grey box. Both now land in AppLog, whose ring buffer is what the "Copy
  // diagnostics" button hands back. The file attaches asynchronously; lines
  // logged before it does are carried across.
  FlutterError.onError = (details) {
    AppLog.error(
      'Flutter error: ${details.exceptionAsString()}',
      stack: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('Uncaught: $error', stack: stack);
    // Logged AND presented: returning true alone would silence the console
    // dump a developer relies on, and the app keeps running either way.
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'AniLocal'),
    );
    return true;
  };
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AppLog.attachFile(logsDirectory, debugEcho: kDebugMode));
  // Awaited: one method-channel call, and it decides the User-Agent every
  // request carries. Unawaited, the first requests went out as
  // `AniLocal/unknown`, which defeats the one signal the services get about
  // which build sent them.
  final info = await PackageInfo.fromPlatform();
  final version = '${info.version}+${info.buildNumber}';
  Diagnostics.appVersion = version;
  aniLocalUserAgent = userAgentFor(version);
  // What we owe for what we ship, reachable from Settings > About > Licences.
  // Flutter collects every pub package's licence for free; these three are
  // the ones it cannot know about: the app's own GPL, the font (its OFL
  // requires the text to travel with the font), and the GPL media stack that
  // media_kit bundles — whose corresponding source is the project repository.
  LicenseRegistry.addLicense(() async* {
    // A missing asset must not take the Licences page down with it — for a
    // GPL build that page IS the notice — so each text falls back to a
    // pointer at the repository, where the same file lives.
    Future<String> text(String asset) async {
      try {
        return await rootBundle.loadString(asset);
      } catch (e) {
        AppLog.error('Licence text $asset missing from the bundle', error: e);
        return 'The text of this licence could not be loaded from the app '
            'bundle. It is the file `$asset` at $kAniLocalProjectUrl.';
      }
    }

    yield LicenseEntryWithLineBreaks(const ['AniLocal'], await text('LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Archivo (font)',
    ], await text('fonts/Archivo-OFL.txt'));
    yield const LicenseEntryWithLineBreaks(
      ['libmpv', 'FFmpeg', 'libass'],
      'AniLocal plays video through libmpv, FFmpeg and libass, bundled by '
      'media_kit (github.com/media-kit/libmpv-darwin-build — the source of '
      'the exact builds shipped, and where their corresponding source is '
      'published). libmpv and FFmpeg are licensed under the GNU GPL version 2 '
      'or later and the GNU LGPL version 2.1 or later; libass under the ISC '
      'licence. Their licence texts follow. AniLocal as a whole is therefore '
      'distributed under the GNU GPL v3 or later, and comes with ABSOLUTELY '
      'NO WARRANTY. Corresponding source for AniLocal: $kAniLocalProjectUrl',
    );
    // The texts themselves: GPLv3's text does not discharge a v2 or LGPL
    // notice, so the media stack's own licences travel in the bundle too.
    yield LicenseEntryWithLineBreaks(const [
      'libmpv',
      'FFmpeg',
    ], await text('third_party/licenses/GPL-2.0.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'libmpv',
      'FFmpeg',
    ], await text('third_party/licenses/LGPL-2.1.txt'));
  });
  AppLog.info(
    'AniLocal starting · schema v${CacheDatabase.currentSchemaVersion} · '
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
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
  // ONE cross-map instance: shared by the AniSkip id backfill and by Jikan's
  // MAL -> AniList enrichment, so the 5.8MB source is fetched and parsed once.
  // ONE HTTP client for the whole app, and it is the one that times out.
  // package:http has no default timeout, so a half-open socket to any of the
  // six services used to hang a scan forever — before the outage guard could
  // even run. Every client accepts an injected client precisely so that this
  // can be decided once, here, rather than six times. Sharing it also means
  // one connection pool and one owner, instead of seven independent clients
  // (two of them for the same art directory) that nothing ever disposed.
  final httpClient = TimeoutClient(http.Client());
  // ONE art cache too — the scan and fix-match used to each build their own
  // for the same directory.
  final artCache = ArtCache(
    directory: coverArtDirectory,
    httpClient: httpClient,
  );
  final crossMap = CrossMapStore(
    directory: derivedDataDirectory,
    httpClient: httpClient,
  );
  // ALL settings live behind one injected object (was ~20 threaded functions).
  // Adding a setting now touches SettingsRepository + its impl + the reader.
  // Built BEFORE the read path and the fill path: both read from it.
  final settings = DriftSettingsRepository(database);
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
    AniSkipSkipProvider(AniSkipClient(httpClient: httpClient)),
  ];
  assert(
    skipProviders.map((p) => p.token).join(',') == kBuiltInSkipOrder.join(','),
    'the shipped skip providers must be in the ONE built-in order',
  );
  // The READ path resolves skips now, so it needs the same ordered, enabled
  // source list the fill path uses — as TOKENS, because the repository must
  // never see a provider (seam #1). Wired here because only the composition
  // root knows which sources this build ships, and read fresh on every query
  // so a reorder, a toggle, or switching cross-checking on takes effect
  // immediately with no refresh and no rescan.
  final repository = DriftLibraryRepository(
    database,
    resolver: volumeResolver,
    skipView: SkipViewSource(
      minLength: settings.loadMinSkipLength,
      activeSources: () async => [
        for (final p in applySourceOrder(
          skipProviders,
          (p) => p.token,
          await settings.loadSkipSourceOrder(),
        ))
          p.token,
      ],
      knownSources: () async => [for (final p in skipProviders) p.token],
      corroborate: settings.loadCorroborateSkips,
    ),
  );
  // The diagnostics report is built HERE because only the composition root can
  // see the database, the repositories and the settings together; the About
  // panel just asks for the string.
  Diagnostics.reportBuilder = () async {
    final series = await repository.allSeries();
    final unmatched = await repository.unmatchedFiles();
    return [
      'schema v${CacheDatabase.currentSchemaVersion}',
      'series: ${series.length} · unmatched files: ${unmatched.length}',
      'skip sources: ${(await settings.loadSkipSourceOrder()).map((p) => '${p.token}:${p.enabled ? 1 : 0}').join(', ')}',
      'cross-check: ${await settings.loadCorroborateSkips()}',
      'min skip: ${(await settings.loadMinSkipLength()).inSeconds}s',
    ].join('\n');
  };
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
    AniListMetadataProvider(
      AniListClient(httpClient: httpClient),
      formatsIn: kEpisodicAnimeFormats,
    ),
    // Keyless, and the only rich source still answering while AniList's API is
    // disabled. Slower, which the two-phase scan hides: placeholders paint from
    // phase 1 before any lookup runs.
    KitsuMetadataProvider(KitsuClient(httpClient: httpClient)),
    // MAL's data with no key — but through a volunteer-run proxy measured at
    // roughly 30% availability, so it is FALLBACK-ONLY and sorts last however
    // the user orders the list. The cross-map supplies the AniList id Jikan
    // doesn't publish, so its answers land on the same identities as everyone
    // else's.
    JikanMetadataProvider(
      JikanClient(httpClient: httpClient),
      crossMap: crossMap,
    ),
    // MyAnimeList is BUILT AND TESTED but deliberately NOT SHIPPED — see
    // `docs/myanimelist-registration.md` for why, and for the registration flow
    // if it comes back. Flipping [kShipMyAnimeListSource] is the whole
    // re-enable: the client, the adapter, the key storage, the key dialog and
    // their tests all stay in the tree and keep running, so none of it rots.
    if (kShipMyAnimeListSource)
      MalMetadataProvider(
        MalClient(httpClient: httpClient, loadClientId: () => malClientId()),
        loadClientId: malClientId,
      ),
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
    art: artCache,
    // ONE ordered skip-source list, mirroring the metadata one. Fetched at
    // scan time only; playback still reads skips from the cache and makes no
    // network call. Chapters, Anime Skip and fingerprinting append here.
    skipProviders: skipProviders,
    loadSkipOrder: settings.loadSkipSourceOrder,
    // Fills a MAL id AniList didn't supply, so auto-skip survives an AniList
    // outage. Fetched lazily and only when something is actually missing.
    crossMap: crossMap,
    resolver: volumeResolver,
  );
  // Fix-match: the ONLY writer of overrides (LibrarySync can't reach it).
  final fixMatch = FixMatchService(
    providers: metadataProviders,
    art: artCache,
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
    final path = normalizeFolderPath(token.path);
    final existing = await database.allFolderRows();
    // Already there, or nested with one that is: refused with the reason,
    // never accepted and quietly re-ranked.
    final refusal = folderRefusal(path, [for (final f in existing) f.path]);
    if (refusal != null) throw refusal;
    await repository.addFolder(path);
    final result = await folderAccess.ensureAccess(path);
    // The CATEGORY grant is reported to the caller (its dialog explains what
    // the folder-wide prompt was about) but not made ambient here: the folder
    // itself reads through the panel's inferred consent, and the banner is
    // for a scan that actually could not read — see [scan].
    if (!result.isDenied) applyAccess(result);
    return (
      added: true,
      deniedLabel: result.isDenied ? result.categoryLabel : null,
    );
  }

  /// The cache could not be opened: set it aside and quit, so the next
  /// launch starts empty. Returns where the broken file went.
  Future<String> resetCache() async {
    await database.close();
    final moved = await quarantineCacheDatabase();
    AppLog.error('Cache reset: moved to $moved');
    return moved;
  }

  /// Which folders are reachable RIGHT NOW: resolve each folder's current
  /// mount, confirm/upgrade its category access, and publish the results the
  /// banners and the greying read. Runs at LAUNCH and at the start of every
  /// scan. It used to run only inside a scan, so a cold start into an
  /// unplugged drive or a revoked permission showed a healthy library with
  /// nothing greyed and no banner until the user happened to press Scan.
  Future<List<LibraryFolderRow>> refreshFolderHealth() async {
    // Folder ROWS (not just paths) carry each folder's volume binding, so we can
    // resolve its CURRENT mount before checking access.
    final folders = await database.allFolderRows();
    // Confirm/upgrade folder-wide access per category (additive — does NOT gate
    // the scan; the scanner still reads each folder via whatever grant it has).
    // Check on the CURRENT mount so a volume that remounted under a NEW name is
    // not mistaken for missing; a truly-unmounted volume (resolves to null)
    // reports missing via its stable path. Same pass records which folder PATHS
    // are currently missing so the UI can grey out shows sourced only there —
    // replaced wholesale each pass, so a replugged folder clears automatically.
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
    return folders;
  }

  Future<SyncSummary> scan(
    void Function() onDiscovered, {
    void Function(SyncProgress progress)? onProgress,
    SyncCancellation? cancellation,
  }) async {
    final folders = await refreshFolderHealth();
    final summary = await sync.sync(
      [for (final f in folders) f.path],
      onDiscovered: onDiscovered,
      onProgress: onProgress,
      cancellation: cancellation,
    );
    // The access banner tells the truth about THIS scan: a category stays
    // flagged only while a folder in it could not be read. Picking
    // ~/Downloads denies the folder-wide grant while the folder itself reads
    // fine through the panel's consent, and the scan used to succeed under a
    // red "Can't access Downloads" that nothing cleared.
    final home = Platform.environment['HOME'] ?? '';
    final failedLabels = {
      for (final path in summary.unreadableFolders)
        ?tccCategoryRoot(path, home)?.label,
    };
    accessIssues.value = [
      for (final label in accessIssues.value)
        if (failedLabels.contains(label)) label,
    ];
    return summary;
  }

  // The playback engine is APP-LIFETIME: built once here, injected, and kept
  // alive across navigation. Leaving the theater now stops it instead of
  // destroying it, so libmpv is constructed once per app run rather than once
  // per visit — see PlaybackController's doc and
  // docs/player-architecture-research.md. `repository` is the WatchOrder
  // resolver (the single "what's next" source) the advance path routes through.
  final playback = PlaybackController(resolver: repository);

  // Folder health for the first frame's banners and greying — not awaited:
  // it opens the database and may ask diskutil, and the library paints from
  // the cache the moment it can; the notifiers update when this lands.
  unawaited(
    refreshFolderHealth().catchError((Object e, StackTrace s) {
      AppLog.warn('Folder health at launch failed', error: e, stack: s);
      return const <LibraryFolderRow>[];
    }),
  );

  // Where the cache lives, for the load-error panel — the one failure that
  // needs to name a file.
  final cachePath = (await cacheDatabaseFile()).path;

  runApp(
    AniLocalApp(
      cachePath: cachePath,
      onResetCache: resetCache,
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
      // The UI relates a folder to a denied category by label without
      // importing the data layer; the home dir is the real one here.
      categoryLabelOf: (path) =>
          tccCategoryRoot(path, Platform.environment['HOME'] ?? '')?.label,
      onOpenAccessSettings: openPrivacyFilesAndFoldersSettings,
    ),
  );
}
