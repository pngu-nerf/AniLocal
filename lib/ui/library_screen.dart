import 'dart:async';
import 'dart:math' as math;

import 'package:anilocal/domain/models/titles.dart' show Titles;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diagnostics/app_log.dart';
import '../domain/folder_health.dart';
import '../domain/missing_episodes.dart';
import '../domain/models/continue_watching.dart';
import '../domain/models/episode.dart';
import '../domain/models/library_snapshot.dart';
import '../domain/models/series.dart';
import '../domain/models/sync_control.dart';
import '../domain/models/sync_summary.dart';
import 'access_recovery.dart';
import 'fix_match_flow.dart';
import 'library/continue_watching_panel.dart';
import 'library/library_layout.dart';
import 'library/library_layout_config.dart';
import 'library/library_search_bar.dart';
import 'library/library_states.dart';
import 'library/series_card.dart';
import 'library_services.dart';
import 'metadata_failure_message.dart';
import 'routes.dart';
import 'settings/settings_actions.dart';
import 'settings/settings_categories.dart';
import 'settings/settings_window.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/guarded.dart';
import 'widgets/notices.dart';

/// Whether a series matches the live library search [query] — a case-insensitive
/// substring of any cached title (English, romaji, or native). A pending
/// placeholder carries its parsed filename/title in [Titles.romaji], so it's
/// searchable too. A blank query matches everything (clearing restores the full
/// library). Pure (UI-layer, filters the already-cached list — no network) so
/// it's unit-testable.
@visibleForTesting
bool seriesMatchesQuery(Series series, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final t = series.titles;
  for (final name in [t.english, t.romaji, t.native]) {
    if (name != null && name.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// "no lookups" / "3 from AniList (lookups)" / "lookups: 3 from AniList, 1
/// from Kitsu". Names the sources that actually answered instead of a fixed
/// one: a scan that fell through to Kitsu because AniList was down otherwise
/// looks identical to one AniList served, and nothing else tells the user.
/// [nameOf] maps a source token to its display name — from the SAME
/// descriptor list the settings page shows, so the two can never call one
/// source different things; an unknown token falls back to itself rather than
/// an invented name. Pure, so the three branches are testable.
@visibleForTesting
String lookupSummary(SyncSummary s, String Function(String token) nameOf) {
  if (s.lookupsBySource.isEmpty) return 'no lookups';
  final byCount = s.lookupsBySource.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final parts = [for (final e in byCount) '${e.value} from ${nameOf(e.key)}'];
  return parts.length == 1
      ? '${parts.first} (lookups)'
      : 'lookups: ${parts.join(', ')}';
}

/// Everything the scan has to say, as ONE message: the summary line, then
/// the unreadable-folder line and the API-failure line when there are any.
/// `problem` is true when either problem line is present (red, longer).
@visibleForTesting
({String text, bool problem}) scanResultText(
  SyncSummary s,
  String Function(String token) nameOf, {
  required Set<String> missing,
}) {
  final lines = [scanSummaryText(s, nameOf)];
  if (s.unreadableFolders.isNotEmpty) {
    lines.add(unreadableFoldersText(s.unreadableFolders, missing: missing));
  }
  if (s.apiFailure case final failure?) {
    lines.add(
      '⚠ ${metadataFailureCause(failure)} '
      'Your library was kept as-is (nothing removed).',
    );
  }
  return (text: lines.join('\n'), problem: lines.length > 1);
}

/// The scan snackbar's summary line.
@visibleForTesting
String scanSummaryText(SyncSummary s, String Function(String token) nameOf) =>
    '${s.filesScanned} scanned · ${s.processed} new '
    '(${s.matched} matched / ${s.unmatched} unmatched) · '
    '${s.unchanged} unchanged · ${s.removed} removed · ${lookupSummary(s, nameOf)}'
    '${s.skipLookupsFailed > 0 ? ' · ${s.skipLookupsFailed} skip lookups failed, will retry' : ''}'
    '${s.sourcesDown.isNotEmpty ? ' · unreachable: ${s.sourcesDown.map(nameOf).join(', ')}' : ''}'
    '${s.cancelled ? ' · stopped early' : ''}';

/// Home: browse the cached library. Reads ONLY from the repository (cache) —
/// instant and offline. Scan (fill path) and add-folder (native picker) are
/// injected callbacks; the UI never imports sync/cache/picker types.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.services,
    required this.onScan,
    required this.accessIssues,
    required this.missingFolders,
    required this.missingFolderPaths,
  });

  /// Every repository and the settings bundle, as ONE object (see
  /// [LibraryServices]).
  final LibraryServices services;

  /// Fill path. The `onDiscovered` callback fires mid-scan, after newly-seen
  /// files are written as pending placeholders but before identification — the
  /// screen wires it to a reload so the grid paints placeholders immediately.
  final ScanRunner onScan;

  /// Shared denied-state (category labels) — drives the banner; the add-dialog
  /// reads the same source via `SourcesActions.onAddFolder`'s result.
  final ValueListenable<List<String>> accessIssues;

  /// Offline drive/mount labels (unplugged drive, offline NAS) — drives the
  /// reconnect banner, distinct from the permission [accessIssues].
  final ValueListenable<List<String>> missingFolders;

  /// Paths of those missing folders — used to grey out shows whose only
  /// sources live there.
  final ValueListenable<Set<String>> missingFolderPaths;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with HeaderPublisher {
  LibraryServices get _services => widget.services;

  /// The cached library. NULL only until the FIRST load arrives — a refresh
  /// assigns the new list on arrival and never clears this, so the grid, the
  /// panel and the search field are never torn down and rebuilt. (This used to
  /// be a `Future` re-assigned in [_reload], which reset the FutureBuilder to
  /// `waiting`, flashed the whole layout through a spinner and dropped the
  /// grid's scroll position. See CLAUDE.md, "never clear known content".)
  List<Series>? _series;

  /// Set when the FIRST load fails; cleared by any later success. Rendered
  /// instead of the spinner, never instead of a list we already have.
  Object? _loadError;
  // Continue-watching entries held in state (not a Future) so the layout knows
  // synchronously whether to allocate the side panel (no entries → no panel).
  List<ContinueWatching> _continueEntries = const [];
  // Live library search. Filtering is in-memory over the already-cached series
  // list — instant, offline, no per-keystroke query (consistent with
  // offline-first). Empty query shows everything.
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // Drives the chunky XP scrollbar over the grid.
  final ScrollController _gridScroll = ScrollController();
  // seriesId -> the next episode to watch. Loaded async; cards show their
  // "Next" affordance once it arrives.
  Map<int, Episode> _upNext = {};
  // seriesId -> the set of library folders its sources live under. Greying is
  // a pure function of this + the live missing-folder set (recomputed in the
  // grid's ValueListenableBuilder, so toggling missing state needs no re-fetch).
  Map<int, Set<String>> _sourceFoldersBySeries = {};
  // seriesId -> downloaded-episode tally for the card's "⬇N of M +X" line.
  Map<int, DownloadTally> _downloadCounts = {};
  bool _continueCollapsed = false;
  // Global homepage visibility toggles (persisted). Default visible; re-read
  // after the Settings dialog closes so a change takes effect immediately.
  bool _showContinueWatching = true;
  bool _showSearchBar = true;

  /// How many library folders exist, from the snapshot: tells the empty
  /// state "nothing found in your folders" from "no folders yet".
  int _folderCount = 0;
  // Live continue-watching panel width. Seeded from the config so the first
  // frame is correct, then overwritten by the persisted (clamped) value.
  double _panelWidth = LibraryLayoutConfig.landingDefault.panelWidth;

  @override
  void initState() {
    super.initState();
    // The scan flag lives in the services so every header shows it; this
    // screen republishes its header when it flips.
    _services.scanning.addListener(_onScanningChanged);
    _services.scan.progress.addListener(_onScanningChanged);
    _services.unmatchedCount.addListener(_onScanningChanged);
    _reload();
    fireAndForget('homepage toggles', _loadHomepageToggles);
    fireAndForget('continue-collapsed setting', () async {
      final v = await _services.settings.loadContinueCollapsed();
      if (mounted) setState(() => _continueCollapsed = v);
    });
    // Already clamped by the repository; the layout clamps again on drag.
    fireAndForget('panel width setting', () async {
      final v = await _services.settings.loadPanelWidth();
      if (mounted) setState(() => _panelWidth = v);
    });
  }

  void _onScanningChanged() {
    if (!mounted) return;
    setState(() {});
    // Folders changed while a scan ran: the rescan they need starts once the
    // running one has ended — after this notification returns, since `end()`
    // is still on the stack.
    if (_rescanQueued && !_services.scanning.value) {
      _rescanQueued = false;
      scheduleMicrotask(() {
        if (mounted) unawaited(_scan());
      });
    }
  }

  /// Set when Settings reported a folder added or removed while a scan was
  /// running. The post-settings scan used to return at the re-entrancy guard
  /// and the new folder was silently never scanned.
  bool _rescanQueued = false;

  @override
  void dispose() {
    _services.scanning.removeListener(_onScanningChanged);
    _services.scan.progress.removeListener(_onScanningChanged);
    _services.unmatchedCount.removeListener(_onScanningChanged);
    _searchController.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _toggleContinueCollapsed() {
    setState(() => _continueCollapsed = !_continueCollapsed);
    unawaited(_services.settings.setContinueCollapsed(_continueCollapsed));
  }

  Future<void> _dismissFromContinue(ContinueWatching entry) =>
      guarded('dismiss from continue watching', () async {
        await _services.watchState.clearProgress(entry.episode);
        _reload();
      });

  /// Monotonic run counter for [_reload]. It is called from eight places, so
  /// runs overlap routinely (mid-scan progress + post-scan, return from the
  /// player + a card tap); without this the OLDER run finishing last won the
  /// `setState` and the grid showed a stale library.
  int _reloadGeneration = 0;

  void _reload() {
    final generation = ++_reloadGeneration;
    // ONE read for everything the screen shows — the series, every card's
    // episodes, continue-watching, up-next, the unmatched count — assigned ON
    // ARRIVAL so the current library stays on screen while the new one loads
    // (CLAUDE.md, "never clear known content"). Five separate reads used to
    // load the same tables five times per repaint; docs/performance.md has the
    // numbers.
    unawaited(
      () async {
        final snapshot = await _services.repository.snapshot();
        final missingEnabled = await _services.settings.loadMissingEnabled();
        if (!mounted || generation != _reloadGeneration) return;
        // Live for every header, not a push-time integer.
        _services.unmatchedCount.value = snapshot.unmatchedCount;
        final stats = _statsFrom(
          snapshot,
          missingEnabled ? snapshot.hidden : const <int, Set<int>>{},
        );
        setState(() {
          _series = snapshot.series;
          _loadError = null;
          _continueEntries = snapshot.continueWatching;
          _upNext = snapshot.upNext;
          _folderCount = snapshot.folderCount;
          _sourceFoldersBySeries = stats.folders;
          _downloadCounts = stats.counts;
        });
      }().then(
        (_) {},
        // Without this, every "cannot open the database" failure — corrupt
        // file, read-only folder, a cache from a newer build, a migration that
        // threw — left `_series` null forever: an eternal spinner, no message,
        // nothing written anywhere. Now it is an error panel with the cause and
        // a way to copy the log.
        onError: (Object e, StackTrace stack) {
          AppLog.error('Library load failed', error: e, stack: stack);
          if (mounted && generation == _reloadGeneration) {
            setState(() => _loadError = e);
          }
        },
      ),
    );
  }

  /// Per-series stats for the grid, derived from the snapshot: the library
  /// folders each show's sources occupy (for greying), and the downloaded-
  /// episode tally for the card's "⬇N of M +X" line. Pure.
  static ({Map<int, Set<String>> folders, Map<int, DownloadTally> counts})
  _statsFrom(LibrarySnapshot snapshot, Map<int, Set<int>> hidden) {
    final folders = <int, Set<String>>{};
    final counts = <int, DownloadTally>{};
    for (final s in snapshot.series) {
      final eps = snapshot.episodesBySeries[s.seriesId] ?? const <Episode>[];
      folders[s.seriesId] = {
        for (final e in eps)
          for (final src in e.sources) src.folderPath,
      };
      // The SAME rule the show page uses, through the same function.
      final slots = computeEpisodeSlots(
        present: eps,
        hidden: hidden[s.seriesId] ?? const <int>{},
        episodeCount: s.episodeCount,
      );
      counts[s.seriesId] = computeDownloadTally(slots, s.episodeCount);
    }
    return (folders: folders, counts: counts);
  }

  HeaderHooks get _header =>
      HeaderHooks(onScan: _scan, onUnmatched: _openUnmatched);

  Future<void> _play(Episode episode, Series series) async {
    // The Continue panel plays straight into the theater; a show whose only
    // drive is unplugged must get the same reconnect hint the card gives.
    final folders = _sourceFoldersBySeries[series.seriesId] ?? const <String>{};
    if (seriesUnavailable(folders, widget.missingFolderPaths.value)) {
      showNotice(
        context,
        "${series.displayTitle} isn't connected. Reconnect its drive, then "
        'scan again.',
        replace: true,
      );
      return;
    }
    await AppRoutes.theater(
      context,
      services: _services,
      series: series,
      episode: episode,
      header: _header,
      onSettings: _openSettings,
    );
    _reload(); // progress/watched/up-next may have changed
  }

  Future<void> _playFromContinue(ContinueWatching entry) =>
      _play(entry.episode, entry.series);

  Future<void> _loadHomepageToggles() async {
    final showContinue = await _services.settings.loadShowContinueWatching();
    final showSearch = await _services.settings.loadShowSearchBar();
    if (mounted) {
      setState(() {
        _showContinueWatching = showContinue;
        _showSearchBar = showSearch;
        // Hiding the search bar clears any active query, so the grid isn't left
        // filtered with no visible way to reset it.
        if (!showSearch && _query.isNotEmpty) {
          _searchController.clear();
          _query = '';
        }
      });
    }
  }

  /// The homepage ⚙ action — the shared app Settings window, identical to the
  /// one the detail page opens from its title bar. Folders is a category in it,
  /// so this is the only header door into it.
  /// Wired to a `VoidCallback` on the header, so every throw in here used to
  /// be a dropped future: guarded, and the user hears about it.
  Future<void> _openSettings({String? initialCategory}) => guarded(
    'settings',
    () => _openSettingsUnguarded(initialCategory: initialCategory),
    onError: (e) {
      if (!mounted) return;
      showFailure(context, "Settings didn't close cleanly.", e);
    },
  );

  Future<void> _openSettingsUnguarded({String? initialCategory}) async {
    final outcome = await showAppSettingsDialog(
      context,
      settings: _services.settings,
      actions: _settingsActions(),
      initialCategory: initialCategory,
    );
    if (!mounted) return;
    // Reflect any change made in the window: homepage-toggle visibility, and a
    // reload (the global "hide next episode" apply-to-all rewrote per-show prefs
    // that the cards render).
    await _loadHomepageToggles();
    if (!mounted) return;
    // A folder added or removed means files to discover or drop, so it needs
    // a SCAN; a pure reorder only re-ranks which copy of a duplicated episode
    // is the default, which the next read re-resolves with no scan and no
    // network.
    if (outcome.sourceSetChanged) {
      if (_services.scanning.value) {
        _rescanQueued = true;
        showNotice(
          context,
          'Folders changed — they will be scanned when the current scan '
          'finishes.',
        );
      } else {
        await _scan();
      }
    } else {
      _reload();
    }
  }

  /// This screen's hooks for the settings window, completing the app-wide
  /// bundle in ONE place.
  SettingsDialogActions _settingsActions() =>
      _services.settingsActions.forScreen(
        onRefreshed: _reload,
        unmatchedCount: _services.unmatchedCount,
        loadUnmatched: _services.repository.unmatchedFiles,
        onFixMatch: (file) async {
          if (await fixMatchFor(context, _services, file) && mounted) {
            _reload();
          }
        },
      );

  Future<void> _scan() async {
    // One scan at a time. The header disables Scan while one runs, but the
    // show page and the theater forward here too, and a second run over the
    // same database is refused by the fill path anyway — this just makes the
    // second tap a no-op instead of an error snackbar.
    if (_services.scanning.value) return;
    final cancellation = _services.scan.begin();
    try {
      // The mid-scan callback paints placeholders the instant they're written
      // (before identification / network), so an offline add shows its anime
      // immediately; the post-scan reload below then shows the upgraded matches.
      // Progress reaches every header through the shared control; Stop
      // cancels through the same token.
      final summary = await widget.onScan(
        () {
          if (mounted) _reload();
        },
        onProgress: _services.scan.report,
        cancellation: cancellation,
      );
      if (!mounted) return;
      // ONE snackbar. The summary, the unreadable folders and the API failure
      // used to queue as three, so the red one appeared only after the first
      // had timed out — by which time the user had looked away.
      final result = scanResultText(
        summary,
        _sourceName,
        missing: _services.missingFolderPaths.value,
      );
      showNotice(
        context,
        result.text,
        duration: result.problem ? kNoticeLong : kNoticeShort,
        replace: true,
        problem: result.problem,
      );
      _reload();
    } catch (e, stack) {
      AppLog.error('Scan failed', error: e, stack: stack);
      if (!mounted) return;
      showFailure(context, 'Scan failed.', e);
    } finally {
      _services.scan.end();
    }
  }

  Future<void> _addFolder() async {
    final sources = _services.settingsActions.sources;
    final ({bool added, String? deniedLabel}) result;
    try {
      result = await sources.onAddFolder();
    } catch (e, stack) {
      // Refused (already added, or nested with one that is) or failed:
      // either way the user hears why, through the one renderer.
      AppLog.warn('Add folder refused or failed', error: e, stack: stack);
      if (!mounted) return;
      showNotice(context, userFacingMessage(e), duration: kNoticeMedium);
      return;
    }
    if (!mounted) return;
    if (result.deniedLabel != null) {
      await showAccessDeniedDialog(
        context,
        result.deniedLabel!,
        sources.onOpenAccessSettings,
      );
    }
    if (result.added && mounted) {
      await _scan(); // onboarding: add -> scan -> done
    }
  }

  String _sourceName(String token) {
    for (final source in _services.settingsActions.metadataSources) {
      if (source.token == token) return source.displayName;
    }
    return token;
  }

  /// Awaited: a fix-match made on the Unmatched screen changes the grid and
  /// the count, so the return reloads — every other pushed screen already did.
  /// The header's Unmatched tab: Settings, opened on its Unmatched category.
  void _openUnmatched() =>
      unawaited(_openSettings(initialCategory: unmatchedCategoryId));

  @override
  Widget build(BuildContext context) {
    publishHeader();
    final scanning = _services.scanning.value;
    return Column(
      children: [
        // Permission-denied banner (Settings recovery).
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.accessIssues,
          builder: (context, labels, _) => labels.isEmpty
              ? const SizedBox.shrink()
              : AccessBanner(
                  labels: labels,
                  onOpenSettings:
                      _services.settingsActions.sources.onOpenAccessSettings,
                  onRescan: scanning ? null : _scan,
                ),
        ),
        // Offline drive/mount banner (reconnect — NOT a permission issue).
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.missingFolders,
          builder: (context, labels, _) => labels.isEmpty
              ? const SizedBox.shrink()
              : ReconnectBanner(
                  labels: labels,
                  onRescan: scanning ? null : _scan,
                ),
        ),
        // Search + continue-watching panel + grid share the page via the
        // composable landing layout (the seam analogous to the theater
        // zones): search pinned full-width on top, panel on the left,
        // grid filling the rest. The cached library is held in state and
        // updated in place; search filters that in-memory list.
        Expanded(
          child: Builder(
            builder: (context) {
              final all = _series;
              // Spinner ONLY before the first load has ever arrived; a
              // refresh keeps the current list on screen.
              if (all == null) {
                final error = _loadError;
                if (error != null) {
                  return LibraryLoadError(
                    error: error,
                    cachePath: _services.cachePath,
                    onReset: _services.onResetCache,
                  );
                }
                return const Center(child: CircularProgressIndicator());
              }
              if (all.isEmpty) {
                // Truly empty library — no search/panel, just onboarding.
                return LibraryEmptyState(
                  scanning: scanning,
                  hasFolders: _folderCount > 0,
                  onAddFolder: _addFolder,
                  onScan: _scan,
                );
              }
              final filtered = [
                for (final s in all)
                  if (seriesMatchesQuery(s, _query)) s,
              ];
              return LibraryLayout(
                config: LibraryLayoutConfig(
                  panelCollapsed: _continueCollapsed,
                  panelWidth: _panelWidth,
                ),
                // Same divider mechanism as the theater rail: live-resize
                // updates the width; drag-end persists it.
                onPanelResize: (w) => setState(() => _panelWidth = w),
                onPanelResizeEnd: () =>
                    _services.settings.setPanelWidth(_panelWidth),
                zones: {
                  // Search bar — hidden by the global homepage toggle.
                  if (_showSearchBar)
                    LibraryZone.search: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Xp.spaceS,
                        Xp.spaceS,
                        Xp.spaceS,
                        Xp.spaceXs,
                      ),
                      child: LibrarySearchBar(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        onClear: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
                  // Continue-watching sidebar — present only when there
                  // are entries AND the global homepage toggle allows it.
                  if (_continueEntries.isNotEmpty && _showContinueWatching)
                    LibraryZone.continueWatching: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Xp.spaceS,
                        Xp.spaceXs,
                        Xp.spaceXs,
                        Xp.spaceS,
                      ),
                      child: ContinueWatchingPanel(
                        entries: _continueEntries,
                        onPlay: _playFromContinue,
                        onDismiss: _dismissFromContinue,
                        collapsed: _continueCollapsed,
                        onToggleCollapsed: _toggleContinueCollapsed,
                      ),
                    ),
                  LibraryZone.grid: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Xp.spaceXs,
                      Xp.spaceXs,
                      Xp.spaceS,
                      Xp.spaceS,
                    ),
                    child: _buildGrid(filtered),
                  ),
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  HeaderSpec buildHeaderSpec() => HeaderSpec(
    title: _services.scanning.value
        ? scanningTitle(_services.scan.progress.value)
        : 'Library',
    actions: AppActions(
      scanning: _services.scanning.value,
      unmatchedCount: _services.unmatchedCount.value,
      onUnmatched: _openUnmatched,
      onScan: _scan,
      onSettings: _openSettings,
      progress: _services.scan.progress.value,
      onStopScan: _services.scanning.value ? _services.scan.stop : null,
      // Unknown until the first snapshot lands: an action fails ABSENT only
      // when its precondition is KNOWN to be gone.
      canScan: _series == null || _folderCount > 0,
    ),
  );

  /// The library grid for the given (already search-filtered) series. Greying
  /// re-evaluates live with the missing-folder set, using the cached per-series
  /// folder map (no re-fetch on toggle). A non-empty library that filters to
  /// nothing shows a "no matches" hint rather than the onboarding empty state.
  Widget _buildGrid(List<Series> series) {
    // The grid lives in a sunken content well (the classic XP inset pane).
    return XpPanel(
      inset: true,
      child: series.isEmpty
          ? NoSearchResults(query: _query)
          : ValueListenableBuilder<Set<String>>(
              valueListenable: widget.missingFolderPaths,
              builder: (context, missing, _) => XpScrollbar(
                controller: _gridScroll,
                child: LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    controller: _gridScroll,
                    padding: _kGridPadding,
                    // The cell is sized EXACTLY to a fixed-aspect poster box
                    // plus a fixed text region, so every card is identically
                    // tall no matter how long its title is. Because the poster
                    // height scales with the tile width while the text region
                    // is a fixed pixel band, no single childAspectRatio works
                    // at every width — so we solve it per-layout.
                    gridDelegate: _posterGridDelegate(constraints.maxWidth),
                    itemCount: series.length,
                    itemBuilder: (_, i) {
                      final folders =
                          _sourceFoldersBySeries[series[i].seriesId] ??
                          const <String>{};
                      return SeriesCard(
                        series: series[i],
                        services: _services,
                        header: _header,
                        nextEpisode: _upNext[series[i].seriesId],
                        downloaded: _downloadCounts[series[i].seriesId],
                        unavailable: seriesUnavailable(folders, missing),
                        onPlay: _play,
                        onReturn: _reload,
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}

/// The scan's "could not read" line, branching on WHY: an unplugged drive
/// wants reconnecting, a folder that exists but refused wants re-adding or a
/// grant. One sentence used to say "re-add the folder" for both — the denied
/// remedy, offered for a mere unplug.
@visibleForTesting
String unreadableFoldersText(
  List<String> unreadable, {
  required Set<String> missing,
}) {
  final gone = [
    for (final p in unreadable)
      if (missing.contains(p)) p,
  ];
  final refused = [
    for (final p in unreadable)
      if (!missing.contains(p)) p,
  ];
  final parts = <String>[
    if (gone.isNotEmpty)
      '${gone.join(", ")} ${gone.length == 1 ? "is" : "are"} not connected — '
          'reconnect the drive and scan again',
    if (refused.isNotEmpty)
      "couldn't read ${refused.join(", ")} — re-add the folder or grant "
          'access in $kFilesAndFoldersPath',
  ];
  return '⚠ ${parts.join('; ')}. Cached items were kept.';
}

/// Grid padding — kept as a named const so the same value feeds both the
/// [GridView] and the column-count math in [_posterGridDelegate].
const EdgeInsets _kGridPadding = EdgeInsets.fromLTRB(
  Xp.spaceL,
  Xp.spaceL,
  Xp.spaceXl,
  Xp.spaceL,
);

/// Reproduces the old `SliverGridDelegateWithMaxCrossAxisExtent(200)` column
/// count, then returns a fixed-count delegate whose `childAspectRatio` makes
/// each cell exactly `posterHeight(tileWidth) + kCardTextRegion` tall.
SliverGridDelegate _posterGridDelegate(double gridWidth) {
  const maxExtent = 200.0;
  const spacing = Xp.spaceL;
  final avail = gridWidth - _kGridPadding.horizontal;
  // Same ceil rule the max-extent delegate uses, so column count is unchanged.
  final count = math.max(1, ((avail + spacing) / (maxExtent + spacing)).ceil());
  final tileWidth = (avail - spacing * (count - 1)) / count;
  final cellHeight = tileWidth / kPosterAspect + kCardTextRegion;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    childAspectRatio: tileWidth / cellHeight,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
  );
}
