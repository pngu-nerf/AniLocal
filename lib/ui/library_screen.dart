import 'dart:async';
import 'dart:math' as math;

import 'package:anilocal/domain/models/titles.dart' show Titles;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/app_log.dart';
import '../diagnostics/diagnostics.dart';
import '../domain/missing_episodes.dart';
import '../domain/models/cache_errors.dart';
import '../domain/models/continue_watching.dart';
import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import '../domain/models/sync_summary.dart';
import 'access_recovery.dart';
import 'library/continue_watching_panel.dart';
import 'library/library_layout.dart';
import 'library/library_layout_config.dart';
import 'library/library_search_bar.dart';
import 'library/series_card.dart';
import 'library_services.dart';
import 'metadata_failure_message.dart';
import 'routes.dart';
import 'settings/settings_actions.dart';
import 'settings/settings_window.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';

/// A show is "unavailable" iff it has source folders AND every one of them is
/// currently missing — a single connected source keeps a multi-source show
/// playable, so it stays un-greyed. Pure (UI-layer) so it's unit-testable.
@visibleForTesting
bool seriesUnavailable(Set<String> sourceFolders, Set<String> missingFolders) =>
    sourceFolders.isNotEmpty && sourceFolders.every(missingFolders.contains);

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

/// The scan snackbar's one line.
@visibleForTesting
String scanSummaryText(SyncSummary s, String Function(String token) nameOf) =>
    '${s.filesScanned} scanned · ${s.processed} new '
    '(${s.matched} matched / ${s.unmatched} unmatched) · '
    '${s.unchanged} unchanged · ${s.removed} removed · ${lookupSummary(s, nameOf)}'
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
  final Future<SyncSummary> Function(void Function() onDiscovered) onScan;

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
  // Count of CONFIRMED-unmatched files — NOT pending placeholders, which
  // auto-resolve. Gates the top-bar Unmatched button.
  int _unmatchedCount = 0;
  // Live continue-watching panel width. Seeded from the config so the first
  // frame is correct, then overwritten by the persisted (clamped) value.
  double _panelWidth = LibraryLayoutConfig.landingDefault.panelWidth;

  @override
  void initState() {
    super.initState();
    // The scan flag lives in the services so every header shows it; this
    // screen republishes its header when it flips.
    _services.scanning.addListener(_onScanningChanged);
    _reload();
    unawaited(_loadHomepageToggles());
    _background(
      'continue-collapsed setting',
      _services.settings.loadContinueCollapsed(),
      (c) => setState(() => _continueCollapsed = c),
    );
    // Already clamped by the repository; the layout clamps again on drag.
    _background(
      'panel width setting',
      _services.settings.loadPanelWidth(),
      (w) => setState(() => _panelWidth = w),
    );
  }

  void _onScanningChanged() {
    if (mounted) setState(() {});
  }

  /// Every secondary read this screen fires goes through here: the value is
  /// applied on arrival if the screen is still mounted, and a failure is
  /// LOGGED and leaves the field as it was. Only the main `allSeries` read
  /// owns the error panel, because that is the one whose absence is a blank
  /// screen; a sibling failing (continue-watching, up-next, a setting) must
  /// not be an uncaught async error.
  void _background<T>(
    String what,
    Future<T> future,
    void Function(T value) apply,
  ) {
    unawaited(
      future.then(
        (v) {
          if (mounted) apply(v);
        },
        onError: (Object e, StackTrace stack) =>
            AppLog.error('Library read failed: $what', error: e, stack: stack),
      ),
    );
  }

  @override
  void dispose() {
    _services.scanning.removeListener(_onScanningChanged);
    _searchController.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _toggleContinueCollapsed() {
    setState(() => _continueCollapsed = !_continueCollapsed);
    unawaited(_services.settings.setContinueCollapsed(_continueCollapsed));
  }

  Future<void> _dismissFromContinue(ContinueWatching entry) async {
    await _services.watchState.clearProgress(entry.episode);
    _reload();
  }

  void _reload() {
    // Assign ON ARRIVAL, exactly like the three fields below — nothing is
    // cleared, so the current library stays on screen while the new one loads.
    unawaited(
      _services.repository.allSeries().then(
        (s) {
          if (!mounted) return;
          setState(() {
            _series = s;
            _loadError = null;
          });
          unawaited(_loadSeriesStats(s));
        },
        // Without this, every "cannot open the database" failure — corrupt
        // file, read-only folder, a cache from a newer build, a migration that
        // threw — left `_series` null forever: an eternal spinner, no message,
        // nothing written anywhere. Now it is an error panel with the cause and
        // a way to copy the log.
        onError: (Object e, StackTrace stack) {
          AppLog.error('Library load failed', error: e, stack: stack);
          if (mounted) setState(() => _loadError = e);
        },
      ),
    );
    // Continue-watching: resolved off the cache into state so the panel's
    // presence (and thus the layout) is known without a FutureBuilder.
    _background(
      'continue watching',
      _services.watchState.continueWatching(),
      (e) => setState(() => _continueEntries = e),
    );
    // "Up Next" per series — resolved off the cache; updates the grid when ready.
    _background(
      'up next',
      _services.watchOrder.upNextBySeries(),
      (m) => setState(() => _upNext = m),
    );
    // Confirmed-unmatched count — gates the top-bar Unmatched button.
    _background(
      'unmatched count',
      _services.repository.unmatchedFiles(),
      (u) => setState(() => _unmatchedCount = u.length),
    );
  }

  /// Monotonic run counter for [_loadSeriesStats]. `_reload` is called from
  /// eight places, so runs overlap routinely; without this the OLDER run
  /// finishing last won the `setState` and the grid showed stale greying and
  /// tallies.
  int _statsGeneration = 0;

  /// Per-series stats for the grid: the library folders each show's sources
  /// occupy (for greying), and the downloaded-episode tally for the card's
  /// "⬇N of M +X" line. Reads existing cached domain state only.
  Future<void> _loadSeriesStats(List<Series> series) async {
    final generation = ++_statsGeneration;
    final missingEnabled = await _services.settings.loadMissingEnabled();
    final allHidden = missingEnabled
        ? await _services.missingEpisodes.allHiddenEpisodes()
        : const <int, Set<int>>{};
    // ONE read for every series, not one per card: `episodesFor` rebuilds the
    // whole library from five tables each time it is called.
    final episodesBySeries = await _services.repository.episodesBySeries();
    if (!mounted || generation != _statsGeneration) return;
    final folders = <int, Set<String>>{};
    final counts = <int, DownloadTally>{};
    for (final s in series) {
      final eps = episodesBySeries[s.seriesId] ?? const <Episode>[];
      folders[s.seriesId] = {
        for (final e in eps)
          for (final src in e.sources) src.folderPath,
      };
      // The SAME rule the show page uses, through the same function.
      final slots = computeEpisodeSlots(
        present: eps,
        hidden: allHidden[s.seriesId] ?? const <int>{},
        episodeCount: s.episodeCount,
      );
      counts[s.seriesId] = computeDownloadTally(slots, s.episodeCount);
    }
    setState(() {
      _sourceFoldersBySeries = folders;
      _downloadCounts = counts;
    });
  }

  HeaderHooks get _header => HeaderHooks(
    onScan: _scan,
    onUnmatched: _openUnmatched,
    unmatchedCount: _unmatchedCount,
  );

  Future<void> _play(Episode episode, Series series) async {
    // The Continue panel plays straight into the theater; a show whose only
    // drive is unplugged must get the same reconnect hint the card gives.
    final folders = _sourceFoldersBySeries[series.seriesId] ?? const <String>{};
    if (seriesUnavailable(folders, widget.missingFolderPaths.value)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              "${series.displayTitle} isn't connected. Reconnect its drive, "
              'then scan again.',
            ),
          ),
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
  Future<void> _openSettings() async {
    final outcome = await showAppSettingsDialog(
      context,
      settings: _services.settings,
      actions: _settingsActions(),
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
      await _scan();
    } else {
      _reload();
    }
  }

  /// This screen's hooks for the settings window, completing the app-wide
  /// bundle in ONE place.
  SettingsDialogActions _settingsActions() =>
      _services.settingsActions.forScreen(
        onRefreshed: _reload,
        loadUnmatchedCount: () async => _unmatchedCount,
        onOpenUnmatched: _openUnmatched,
      );

  Future<void> _scan() async {
    // One scan at a time. The header disables Scan while one runs, but the
    // show page and the theater forward here too, and a second run over the
    // same database is refused by the fill path anyway — this just makes the
    // second tap a no-op instead of an error snackbar.
    if (_services.scanning.value) return;
    _services.scanning.value = true;
    try {
      // The mid-scan callback paints placeholders the instant they're written
      // (before identification / network), so an offline add shows its anime
      // immediately; the post-scan reload below then shows the upgraded matches.
      final summary = await widget.onScan(() {
        if (mounted) _reload();
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text(scanSummaryText(summary, _sourceName))),
      );
      if (summary.unreadableFolders.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: Xp.error,
            content: Text(
              '⚠ Could not read: ${summary.unreadableFolders.join(", ")}. '
              'Re-add the folder to restore access (its cached items were kept).',
            ),
          ),
        );
      }
      final apiFailure = summary.apiFailure;
      if (apiFailure != null) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: Xp.error,
            content: Text(
              '⚠ ${metadataFailureCause(apiFailure)} '
              'Your library was kept as-is (nothing removed).',
            ),
          ),
        );
      }
      _reload();
    } catch (e, stack) {
      AppLog.error('Scan failed', error: e, stack: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed. ${userFacingMessage(e)}'),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      _services.scanning.value = false;
    }
  }

  Future<void> _addFolder() async {
    final sources = _services.settingsActions.sources;
    final result = await sources.onAddFolder();
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

  void _openUnmatched() =>
      unawaited(AppRoutes.unmatched(context, services: _services));

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
                if (error != null) return _LoadErrorState(error: error);
                return const Center(child: CircularProgressIndicator());
              }
              if (all.isEmpty) {
                // Truly empty library — no search/panel, just onboarding.
                return _EmptyState(scanning: scanning, onAddFolder: _addFolder);
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
    title: 'Library',
    actions: AppActions(
      scanning: _services.scanning.value,
      unmatchedCount: _unmatchedCount,
      onUnmatched: _openUnmatched,
      onScan: _scan,
      onSettings: _openSettings,
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
          ? _NoSearchResults(query: _query)
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

/// Shown when the library has shows but the live search matched none.
class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Xp.spaceXl),
        child: Text(
          'No shows match “${query.trim()}”.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeTitle),
        ),
      ),
    );
  }
}

/// The library could not be read at all. Distinguishes the ONE failure with
/// a specific remedy (a cache from a newer build → update the app) from every
/// other, and hands the user the log so a report contains evidence.
class _LoadErrorState extends StatefulWidget {
  const _LoadErrorState({required this.error});

  final Object error;

  @override
  State<_LoadErrorState> createState() => _LoadErrorStateState();
}

class _LoadErrorStateState extends State<_LoadErrorState> {
  String _copyLabel = 'Copy diagnostics';

  /// The same report Settings › About produces — one payload for one button
  /// label — awaited so the label can confirm, and caught so the screen whose
  /// whole job is "report this" cannot fail silently at the clipboard.
  Future<void> _copy() async {
    try {
      final report = await Diagnostics.report();
      await Clipboard.setData(
        ClipboardData(text: '$report\n\n--- error ---\n${widget.error}'),
      );
      if (mounted) setState(() => _copyLabel = 'Copied');
    } catch (e, stack) {
      AppLog.error('Copy diagnostics failed', error: e, stack: stack);
      if (mounted) setState(() => _copyLabel = 'Copy failed — see log file');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final newer = error is CacheNewerThanAppException;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            newer
                ? 'This library was created by a newer version of AniLocal.'
                : "Couldn't open the library cache.",
            style: const TextStyle(color: Xp.text, fontSize: Xp.fontSizeTitle),
          ),
          const SizedBox(height: 10),
          Text(
            newer ? 'Update the app to open it.' : '$error',
            style: const TextStyle(
              color: Xp.textDim,
              fontSize: Xp.fontSizeBody,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Xp.spaceL),
          XpButton(
            icon: Icons.copy_outlined,
            label: _copyLabel,
            onPressed: _copy,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, required this.onAddFolder});

  final bool scanning;
  final Future<void> Function() onAddFolder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your library is empty.',
            style: TextStyle(color: Xp.text, fontSize: Xp.fontSizeTitle),
          ),
          const SizedBox(height: Xp.spaceL),
          XpButton(
            icon: Icons.create_new_folder_outlined,
            label: 'Add your first folder',
            onPressed: scanning ? null : onAddFolder,
          ),
          const SizedBox(height: 10),
          const Text(
            'Point AniLocal at a folder of anime — it scans it for you.',
            style: TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeBody),
          ),
        ],
      ),
    );
  }
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
