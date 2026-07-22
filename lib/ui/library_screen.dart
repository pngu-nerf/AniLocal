import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/continue_watching.dart';
import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import '../domain/models/skip_mode.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'access_recovery.dart';
import 'folders_screen.dart';
import 'library/continue_watching_panel.dart';
import 'library/library_layout.dart';
import 'library/library_layout_config.dart';
import 'library/library_search_bar.dart';
import 'series_detail_screen.dart';
import 'settings_dialog.dart';
import 'theater/theater_screen.dart';
import 'theme/header_readout.dart';
import 'theme/xp_theme.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'unmatched_screen.dart';
import 'widgets/header_actions.dart';

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

/// Stage 4/5 home: browse the cached library. Reads ONLY from the repository
/// (cache) — instant and offline. Scan (fill path) and add-folder (native
/// picker) are injected callbacks; the UI never imports sync/cache/picker types.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.missing,
    required this.loadMissingEnabled,
    required this.setMissingEnabled,
    required this.onScan,
    required this.onRefreshMetadata,
    required this.onAddFolder,
    required this.accessIssues,
    required this.missingFolders,
    required this.missingFolderPaths,
    required this.onOpenAccessSettings,
    required this.loadContinueCollapsed,
    required this.setContinueCollapsed,
    required this.loadAutoPlayNext,
    required this.setAutoPlayNext,
    required this.loadSkipMode,
    required this.setSkipMode,
    required this.loadRailFraction,
    required this.setRailFraction,
    required this.loadPanelFraction,
    required this.setPanelFraction,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (missing-episodes feature); passed through to the
  /// detail screen and read here to exclude hidden episodes from card counts.
  final MissingEpisodesRepository missing;

  /// Missing-episodes feature toggle (persisted, default on). Governs ghost
  /// tiles, the Hidden tab, and whether hidden episodes affect completeness.
  final Future<bool> Function() loadMissingEnabled;
  final Future<void> Function(bool enabled) setMissingEnabled;

  /// Fill path. [onDiscovered] fires mid-scan, after newly-seen files are
  /// written as pending placeholders but before identification — the screen
  /// wires it to a reload so the grid paints placeholders immediately.
  final Future<SyncSummary> Function(void Function() onDiscovered) onScan;

  /// Re-fetch metadata (idMal + skip data) for cached series — no file scan, no
  /// pruning, preserves overrides/watch-state. Returns counts for a snackbar.
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

  /// Load/persist the collapsed state of the "Continue watching" section.
  final Future<bool> Function() loadContinueCollapsed;
  final Future<void> Function(bool collapsed) setContinueCollapsed;

  /// Auto-play-next setting (persisted); read by the player, toggled here.
  final Future<bool> Function() loadAutoPlayNext;
  final Future<void> Function(bool enabled) setAutoPlayNext;

  /// Skip mode (off/button/auto), persisted; read by the player, set here.
  final Future<SkipMode> Function() loadSkipMode;
  final Future<void> Function(SkipMode mode) setSkipMode;

  /// Theater rail width (fraction), persisted; the rail divider reads/writes it.
  final Future<double> Function() loadRailFraction;
  final Future<void> Function(double fraction) setRailFraction;

  /// Continue-watching panel width (fraction), persisted; the panel divider
  /// reads/writes it — the landing-page analogue of the rail fraction above.
  final Future<double> Function() loadPanelFraction;
  final Future<void> Function(double fraction) setPanelFraction;

  /// Opens the native folder picker; reports whether a folder was added and the
  /// denied TCC category label (if the folder's category access was refused).
  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  /// Shared denied-state (category labels) — drives the banner; the add-dialog
  /// reads the same source via [onAddFolder]'s result.
  final ValueListenable<List<String>> accessIssues;

  /// Offline drive/mount labels (unplugged drive, offline NAS) — drives the
  /// reconnect banner, distinct from the permission [accessIssues].
  final ValueListenable<List<String>> missingFolders;

  /// Paths of those missing folders — used to grey out shows whose only
  /// sources live there.
  final ValueListenable<Set<String>> missingFolderPaths;

  final Future<bool> Function() onOpenAccessSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<Series>> _series;
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
  // anilistId -> the next episode to watch (relations-aware). Loaded async;
  // cards show their "Next" affordance once it arrives.
  Map<int, Episode> _upNext = {};
  // anilistId -> the set of library folders its sources live under. Greying is
  // a pure function of this + the live missing-folder set (recomputed in the
  // grid's ValueListenableBuilder, so toggling missing state needs no re-fetch).
  Map<int, Set<String>> _sourceFoldersBySeries = {};
  // anilistId -> downloaded-episode tally for the card's "⬇N of M +X" line:
  // inRange = downloaded eps whose anchored position is within 1..episodeCount;
  // outOfRange = the rest (position > count, or unanchored); total = the
  // completeness denominator (episodeCount minus any hidden in-range positions
  // when the missing-episodes feature is on, else episodeCount; null if unknown).
  // Loaded async alongside the source folders (same episodesFor read).
  Map<int, ({int inRange, int outOfRange, int? total})> _downloadCounts = {};
  bool _scanning = false;
  bool _continueCollapsed = false;
  // Count of CONFIRMED-unmatched files (AniList said no) — NOT pending
  // placeholders, which auto-resolve. Gates the top-bar Unmatched button; the
  // Settings → Metadata entry is always shown regardless.
  int _unmatchedCount = 0;
  // Live continue-watching panel width. Seeded from the config so the first
  // frame is correct, then overwritten by the persisted (clamped) value.
  double _panelFraction = LibraryLayoutConfig.landingDefault.panelFraction;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.loadContinueCollapsed().then((c) {
      if (mounted) setState(() => _continueCollapsed = c);
    });
    widget.loadPanelFraction().then((f) {
      final clamped = f.clamp(
        LibraryLayoutConfig.panelFractionMin,
        LibraryLayoutConfig.panelFractionMax,
      );
      if (mounted) setState(() => _panelFraction = clamped);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _toggleContinueCollapsed() {
    setState(() => _continueCollapsed = !_continueCollapsed);
    widget.setContinueCollapsed(_continueCollapsed);
  }

  Future<void> _dismissFromContinue(ContinueWatching entry) async {
    await widget.watchState.clearProgress(entry.episode);
    _reload();
  }

  void _reload() {
    setState(() {
      _series = widget.repository.allSeries();
    });
    // Continue-watching: resolved off the cache into state so the panel's
    // presence (and thus the layout) is known without a FutureBuilder.
    widget.watchState.continueWatching().then((e) {
      if (mounted) setState(() => _continueEntries = e);
    });
    // "Up Next" per series — resolved off the cache; updates the grid when ready.
    widget.watchOrder.upNextBySeries().then((m) {
      if (mounted) setState(() => _upNext = m);
    });
    // Confirmed-unmatched count — gates the top-bar Unmatched button.
    widget.repository.unmatchedFiles().then((u) {
      if (mounted) setState(() => _unmatchedCount = u.length);
    });
    _loadSeriesStats();
  }

  /// Per-series stats derived from one `episodesFor` read each: the library
  /// folders each show's sources occupy (for greying), and the downloaded-
  /// episode tally (in-range vs out-of-range) for the card's "⬇N of M +X" line.
  /// Reads existing cached domain state only — pure display, no schema change.
  Future<void> _loadSeriesStats() async {
    final series = await _series;
    // Hidden episodes are excluded from the completeness count when the feature
    // is on (consistent with the show page); off → no exclusion. One read for
    // the whole grid (a series absent from the map has nothing hidden).
    final missingEnabled = await widget.loadMissingEnabled();
    final allHidden = missingEnabled
        ? await widget.missing.allHiddenEpisodes()
        : const <int, Set<int>>{};
    final folders = <int, Set<String>>{};
    final counts = <int, ({int inRange, int outOfRange, int? total})>{};
    for (final s in series) {
      final eps = await widget.repository.episodesFor(s.anilistId);
      folders[s.anilistId] = {
        for (final e in eps)
          for (final src in e.sources) src.folderPath,
      };
      // In-range = anchored position within 1..episodeCount; out-of-range =
      // everything else (position > count, or unanchored/0). One logical
      // episode per entry (episodesFor is de-duplicated), so the two partition
      // the download count. When the AniList total is unknown we can't judge
      // range, so treat all as in-range (the card then shows just "⬇N").
      // Hidden positions drop out of the count AND reduce the denominator, so
      // hiding the only missing episode reads "11 of 11" (same rule the show
      // page uses via computeDownloadTally).
      final hidden = allHidden[s.anilistId] ?? const <int>{};
      final m = s.episodeCount;
      var inRange = 0;
      var outOfRange = 0;
      var hiddenInRange = 0;
      for (final e in eps) {
        if (hidden.contains(e.anchoredNumber)) continue;
        if (m == null || (e.anchoredNumber >= 1 && e.anchoredNumber <= m)) {
          inRange++;
        } else {
          outOfRange++;
        }
      }
      if (m != null) {
        for (final h in hidden) {
          if (h >= 1 && h <= m) hiddenInRange++;
        }
      }
      counts[s.anilistId] = (
        inRange: inRange,
        outOfRange: outOfRange,
        total: m == null ? null : m - hiddenInRange,
      );
    }
    if (mounted) {
      setState(() {
        _sourceFoldersBySeries = folders;
        _downloadCounts = counts;
      });
    }
  }

  Future<void> _play(Episode episode, Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TheaterScreen(
          series: series,
          initialEpisode: episode,
          repository: widget.repository,
          watchState: widget.watchState,
          watchOrder: widget.watchOrder,
          loadAutoPlayNext: widget.loadAutoPlayNext,
          loadSkipMode: widget.loadSkipMode,
          loadRailFraction: widget.loadRailFraction,
          setRailFraction: widget.setRailFraction,
        ),
      ),
    );
    _reload(); // progress/watched/up-next may have changed
  }

  Future<void> _playFromContinue(ContinueWatching entry) =>
      _play(entry.episode, entry.series);

  /// The homepage entry to the shared app Settings dialog (identical to the one
  /// the detail page opens from its title bar).
  Future<void> _openSettings() => showAppSettingsDialog(
    context,
    SettingsActions(
      loadAutoPlayNext: widget.loadAutoPlayNext,
      setAutoPlayNext: widget.setAutoPlayNext,
      loadSkipMode: widget.loadSkipMode,
      setSkipMode: widget.setSkipMode,
      loadMissingEnabled: widget.loadMissingEnabled,
      setMissingEnabled: widget.setMissingEnabled,
      onRefreshMetadata: widget.onRefreshMetadata,
      onRefreshed: _reload,
      loadUnmatchedCount: () async => _unmatchedCount,
      onOpenUnmatched: _openUnmatched,
    ),
  );

  Future<Set<String>> _folderPaths() async =>
      (await widget.repository.watchedFolders()).map((f) => f.path).toSet();

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      // The mid-scan callback paints placeholders the instant they're written
      // (before identification / network), so an offline add shows its anime
      // immediately; the post-scan reload below then shows the upgraded matches.
      final summary = await widget.onScan(() {
        if (mounted) _reload();
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(_summaryText(summary))));
      if (summary.unreadableFolders.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: Text(
              '⚠ Could not read: ${summary.unreadableFolders.join(", ")}. '
              'Re-add the folder to restore access (its cached items were kept).',
            ),
          ),
        );
      }
      if (summary.apiUnreachable) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: const Text(
              "⚠ Couldn't reach AniList — your library was kept as-is "
              '(nothing removed). Check your connection and rescan.',
            ),
          ),
        );
      }
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addFolder() async {
    final result = await widget.onAddFolder();
    if (!mounted) return;
    if (result.deniedLabel != null) {
      await showAccessDeniedDialog(
        context,
        result.deniedLabel!,
        widget.onOpenAccessSettings,
      );
    }
    if (result.added && mounted) {
      await _scan(); // onboarding: add -> scan -> done
    }
  }

  String _summaryText(SyncSummary s) =>
      '${s.filesScanned} scanned · ${s.processed} new '
      '(${s.matched} matched / ${s.unmatched} unmatched) · '
      '${s.unchanged} unchanged · ${s.removed} removed · '
      '${s.anilistLookups} AniList lookups';

  /// Open the folders manager, then rescan iff the folder SET changed (a pure
  /// reorder just reloads to re-resolve default sources — no scan, no network).
  Future<void> _openFolders() async {
    final before = await _folderPaths();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoldersScreen(
          repository: widget.repository,
          onAddFolder: widget.onAddFolder,
          onOpenAccessSettings: widget.onOpenAccessSettings,
        ),
      ),
    );
    if (!mounted) return;
    final after = await _folderPaths();
    if (!setEquals(before, after)) {
      await _scan();
    } else {
      _reload();
    }
  }

  void _openUnmatched() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => UnmatchedScreen(
        repository: widget.repository,
        fixMatch: widget.fixMatch,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The blackout-XP look is scoped to this screen's subtree: pushed routes
    // (detail, theater, folders) sit above this Theme on the app's Navigator,
    // so they keep the current theme until we style them in a later pass.
    return Theme(
      data: XpTheme.data(),
      child: Scaffold(
        backgroundColor: Xp.desktop,
        // No desktop "margin": the XP window now fills the OS window (we hid the
        // native title bar), so our blue title bar reaches the window's top edge
        // and the traffic lights sit centered within it.
        body: XpWindow(
          caption: 'AniLocal',
          // Branding is the header VFD readout — a lit dot-matrix "screen" in
          // the chassis. Idle on the library it reads "AniLocal LIBRARY".
          captionWidget: const HeaderReadout(title: 'Library'),
          // The app actions live at the title bar's TOP-RIGHT — the SAME shared
          // bar every header screen uses, so the header looks identical
          // everywhere (only the back button differs).
          titleTrailing: HeaderActionsBar(
            scanning: _scanning,
            unmatchedCount: _unmatchedCount,
            onFolders: _openFolders,
            onUnmatched: _openUnmatched,
            onScan: _scan,
            onSettings: _openSettings,
          ),
          child: Column(
            children: [
              // Permission-denied banner (Settings recovery).
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.accessIssues,
                builder: (context, labels, _) => labels.isEmpty
                    ? const SizedBox.shrink()
                    : AccessBanner(
                        labels: labels,
                        onOpenSettings: widget.onOpenAccessSettings,
                        onRescan: _scanning ? () {} : _scan,
                      ),
              ),
              // Offline drive/mount banner (reconnect — NOT a permission issue).
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.missingFolders,
                builder: (context, labels, _) => labels.isEmpty
                    ? const SizedBox.shrink()
                    : ReconnectBanner(
                        labels: labels,
                        onRescan: _scanning ? () {} : _scan,
                      ),
              ),
              // Search + continue-watching panel + grid share the page via the
              // composable landing layout (the seam analogous to the theater
              // zones): search pinned full-width on top, panel on the left,
              // grid filling the rest. The one FutureBuilder resolves the
              // cached library once; search filters that in-memory list.
              Expanded(
                child: FutureBuilder<List<Series>>(
                  future: _series,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snapshot.data ?? const <Series>[];
                    if (all.isEmpty) {
                      // Truly empty library — no search/panel, just onboarding.
                      return _EmptyState(
                        scanning: _scanning,
                        onAddFolder: _addFolder,
                      );
                    }
                    final filtered = [
                      for (final s in all)
                        if (seriesMatchesQuery(s, _query)) s,
                    ];
                    return LibraryLayout(
                      config: LibraryLayoutConfig(
                        panelCollapsed: _continueCollapsed,
                        panelFraction: _panelFraction,
                      ),
                      // Same divider mechanism as the theater rail: live-resize
                      // updates the fraction; drag-end persists it.
                      onPanelResize: (f) => setState(() => _panelFraction = f),
                      onPanelResizeEnd: () =>
                          widget.setPanelFraction(_panelFraction),
                      zones: {
                        LibraryZone.search: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: LibrarySearchBar(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            onClear: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                        ),
                        if (_continueEntries.isNotEmpty)
                          LibraryZone.continueWatching: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
                            child: ContinueWatchingPanel(
                              entries: _continueEntries,
                              onPlay: _playFromContinue,
                              onDismiss: _dismissFromContinue,
                              collapsed: _continueCollapsed,
                              onToggleCollapsed: _toggleContinueCollapsed,
                            ),
                          ),
                        LibraryZone.grid: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                          child: _buildGrid(filtered),
                        ),
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                    // The cell is sized EXACTLY to a fixed-aspect poster box plus a
                    // fixed text region, so every card is identically tall no matter
                    // how long its title is. Because the poster height scales with
                    // the tile width while the text region is a fixed pixel band,
                    // no single childAspectRatio works at every width — so we solve
                    // it per-layout: reproduce the old max-extent column count, then
                    // derive the aspect ratio from this width's actual tile width.
                    gridDelegate: _posterGridDelegate(constraints.maxWidth),
                    itemCount: series.length,
                    itemBuilder: (_, i) {
                      final folders =
                          _sourceFoldersBySeries[series[i].anilistId] ??
                          const <String>{};
                      final unavailable = seriesUnavailable(folders, missing);
                      return _SeriesCard(
                        series: series[i],
                        repository: widget.repository,
                        fixMatch: widget.fixMatch,
                        watchState: widget.watchState,
                        sourceSelection: widget.sourceSelection,
                        watchOrder: widget.watchOrder,
                        // `missing` (local) is the missing-FOLDER set above;
                        // the repository is `widget.missing`.
                        missingRepo: widget.missing,
                        loadMissingEnabled: widget.loadMissingEnabled,
                        setMissingEnabled: widget.setMissingEnabled,
                        onRefreshMetadata: widget.onRefreshMetadata,
                        nextEpisode: _upNext[series[i].anilistId],
                        downloaded: _downloadCounts[series[i].anilistId],
                        unavailable: unavailable,
                        onPlay: _play,
                        loadAutoPlayNext: widget.loadAutoPlayNext,
                        setAutoPlayNext: widget.setAutoPlayNext,
                        loadSkipMode: widget.loadSkipMode,
                        setSkipMode: widget.setSkipMode,
                        loadRailFraction: widget.loadRailFraction,
                        setRailFraction: widget.setRailFraction,
                        onReturn: _reload,
                        onFolders: _openFolders,
                        onScan: _scan,
                        onUnmatched: _openUnmatched,
                        unmatchedCount: _unmatchedCount,
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
        padding: const EdgeInsets.all(24),
        child: Text(
          'No shows match “${query.trim()}”.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Xp.textDim, fontSize: 14),
        ),
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
            style: TextStyle(color: Xp.text, fontSize: 15),
          ),
          const SizedBox(height: 16),
          XpButton(
            icon: Icons.create_new_folder_outlined,
            label: 'Add your first source',
            onPressed: scanning ? null : onAddFolder,
          ),
          const SizedBox(height: 10),
          const Text(
            'Point AniLocal at a folder of anime — it syncs automatically.',
            style: TextStyle(color: Xp.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Poster aspect ratio (width / height) for every library card's cover.
///
/// Verified against the cached AniList art: `coverImage.extraLarge` is 460px
/// wide with heights clustering at 650 (≈0.707) and ranging 0.667–0.711 — i.e.
/// the covers are NOT a single ratio. We fix the box to the dominant 460×650
/// and [BoxFit.cover] it — the cover FILLS the box (full-bleed, no gaps),
/// cropping whichever dimension overflows. Because the box is already a proper
/// ~2:3 poster shape, a normal cover fills with negligible crop; only a
/// genuinely off-ratio poster crops slightly (acceptable — no empty side/top
/// gaps). Every card's poster is identically sized.
const double _kPosterAspect = 460 / 650;

/// Title font size + line height for a card, shared with [_kTitleBlockHeight]
/// so the reserved title block is exactly two lines tall.
const double _kCardTitleFontSize = 13;
const double _kCardTitleLineHeight = 1.25;

/// Height of the ALWAYS-two-lines title block. Reserving two lines even for a
/// one-line title (its second line stays empty) keeps the meta/download line
/// below it pinned to the same vertical position on every card, regardless of
/// title length.
const double _kTitleBlockHeight =
    _kCardTitleFontSize * _kCardTitleLineHeight * 2; // 32.5

/// Fixed height of the text band under the poster: the two-line title block, a
/// small gap, and one meta line — plus a little headroom. Fixed (and fed to the
/// grid delegate) so every card is uniform total height regardless of title
/// length; a short title just leaves slack inside its reserved title block.
const double _kCardTextRegion = 6 + _kTitleBlockHeight + 2 + 15; // ≈55.5

/// Grid padding — kept as a named const so the same value feeds both the
/// [GridView] and the column-count math in [_posterGridDelegate].
const EdgeInsets _kGridPadding = EdgeInsets.fromLTRB(16, 16, 24, 16);

/// Reproduces the old `SliverGridDelegateWithMaxCrossAxisExtent(200)` column
/// count, then returns a fixed-count delegate whose `childAspectRatio` makes
/// each cell exactly `posterHeight(tileWidth) + _kCardTextRegion` tall.
SliverGridDelegate _posterGridDelegate(double gridWidth) {
  const maxExtent = 200.0;
  const spacing = 16.0;
  final avail = gridWidth - _kGridPadding.horizontal;
  // Same ceil rule the max-extent delegate uses, so column count is unchanged.
  final count = math.max(1, ((avail + spacing) / (maxExtent + spacing)).ceil());
  final tileWidth = (avail - spacing * (count - 1)) / count;
  final cellHeight = tileWidth / _kPosterAspect + _kCardTextRegion;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    childAspectRatio: tileWidth / cellHeight,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
  );
}

class _SeriesCard extends StatefulWidget {
  const _SeriesCard({
    required this.series,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.missingRepo,
    required this.loadMissingEnabled,
    required this.setMissingEnabled,
    required this.onRefreshMetadata,
    required this.nextEpisode,
    required this.downloaded,
    required this.unavailable,
    required this.onPlay,
    required this.loadAutoPlayNext,
    required this.setAutoPlayNext,
    required this.loadSkipMode,
    required this.setSkipMode,
    required this.loadRailFraction,
    required this.setRailFraction,
    required this.onReturn,
    // Header actions forwarded to the detail screen so its header matches home.
    required this.onFolders,
    required this.onScan,
    required this.onUnmatched,
    required this.unmatchedCount,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;
  final MissingEpisodesRepository missingRepo;
  final Future<bool> Function() loadMissingEnabled;
  final Future<void> Function(bool enabled) setMissingEnabled;
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

  /// The next episode to watch for this series (relations-aware), or null when
  /// the series isn't started / has nothing next. Drives the "Next" button.
  final Episode? nextEpisode;

  /// Downloaded-episode tally for the "⬇N of M +X" metadata line: in-range vs
  /// out-of-range counts, and the completeness denominator (M minus hidden
  /// in-range positions). Null while the async stats load (the line then shows
  /// just the show-type until it arrives — no wrong numbers flashed).
  final ({int inRange, int outOfRange, int? total})? downloaded;

  /// True when every source folder of this show is currently missing (offline
  /// drive/NAS): dimmed + marked, and a tap shows a reconnect hint rather than
  /// opening it. Still listed in place (cached art/metadata shown).
  final bool unavailable;
  final Future<void> Function(Episode, Series) onPlay;
  final Future<bool> Function() loadAutoPlayNext;
  final Future<void> Function(bool enabled) setAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;
  final Future<void> Function(SkipMode mode) setSkipMode;
  final Future<double> Function() loadRailFraction;
  final Future<void> Function(double fraction) setRailFraction;
  final VoidCallback onReturn;

  /// Header actions forwarded to the detail screen (Sources / Sync / Unmatched)
  /// so its header matches the home header. [unmatchedCount] is a snapshot.
  final Future<void> Function() onFolders;
  final Future<void> Function() onScan;
  final VoidCallback onUnmatched;
  final int unmatchedCount;

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  bool _hover = false;

  Future<void> _open(BuildContext context, String title) async {
    if (widget.unavailable) {
      // Fail gracefully with a reconnect hint (consistent with the banner) —
      // don't open into a screen that can't play anything.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              "$title isn't connected. Reconnect its drive, then rescan.",
            ),
          ),
        );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(
          series: widget.series,
          repository: widget.repository,
          fixMatch: widget.fixMatch,
          watchState: widget.watchState,
          sourceSelection: widget.sourceSelection,
          watchOrder: widget.watchOrder,
          missing: widget.missingRepo,
          loadMissingEnabled: widget.loadMissingEnabled,
          setMissingEnabled: widget.setMissingEnabled,
          onRefreshMetadata: widget.onRefreshMetadata,
          loadAutoPlayNext: widget.loadAutoPlayNext,
          setAutoPlayNext: widget.setAutoPlayNext,
          loadSkipMode: widget.loadSkipMode,
          setSkipMode: widget.setSkipMode,
          loadRailFraction: widget.loadRailFraction,
          setRailFraction: widget.setRailFraction,
          onFolders: widget.onFolders,
          onScan: widget.onScan,
          onUnmatched: widget.onUnmatched,
          unmatchedCount: widget.unmatchedCount,
        ),
      ),
    );
    widget.onReturn(); // continue-watching / up-next may have changed
  }

  /// The metadata line: "ShowType · ⬇N of M +X". Keeps the show-type + middot;
  /// replaces the old scraped-count segment with the downloaded-episodes tally.
  /// Only the "+X" (extra out-of-range downloads) is coloured (amber attention);
  /// the "⬇N of M" is neutral. `maxLines: 1` + ellipsis degrades gracefully on a
  /// cramped card — the tail (the +X) drops first, never overflowing. The
  /// unavailable / pending states keep their plain copy.
  Widget _metaLine(Series series, bool unavailable) {
    const style = TextStyle(color: Xp.textDim, fontSize: 11, height: 1.2);
    const one = TextOverflow.ellipsis;
    if (unavailable) {
      return const Text(
        'Unavailable — not connected',
        maxLines: 1,
        overflow: one,
        style: style,
      );
    }
    if (series.pending) {
      return const Text(
        'Identifying…',
        maxLines: 1,
        overflow: one,
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    if (series.format != null) spans.add(TextSpan(text: series.format));
    final dl = widget.downloaded;
    if (dl != null) {
      // The completeness denominator already accounts for hidden episodes (see
      // _loadSeriesStats); null when the AniList total is unknown.
      final m = dl.total;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
      // A flat, single-color Material icon (not the ⬇ emoji, which the OS draws
      // full-color with a box). Rendered inline via a WidgetSpan, sized to the
      // text and explicitly given the line's neutral color (a WidgetSpan child
      // doesn't inherit the surrounding TextSpan style) so it stays consistent.
      spans.add(
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(Icons.download, size: 13, color: Xp.textDim),
          ),
        ),
      );
      // "N of M" — the AniList total M is dropped when unknown (rare) → just "N".
      spans.add(
        TextSpan(text: m != null ? '${dl.inRange} of $m' : '${dl.inRange}'),
      );
      if (dl.outOfRange > 0) {
        spans.add(
          TextSpan(
            text: ' +${dl.outOfRange}',
            style: const TextStyle(color: Xp.warning),
          ),
        );
      }
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: one,
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final unavailable = widget.unavailable;
    final next = widget.nextEpisode;
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;
    // Inverted card: the poster is the FIXED element — a 2:3 box showing the
    // whole cover, uncropped and identical across every card — sitting in a
    // sunken bevel frame that pops out (raised) on hover (the tactile XP cue
    // that it's a button). Below it a fixed-height text band keeps card heights
    // uniform regardless of title length. The "Next" affordance is a beveled
    // footer strip OVERLAID on the poster's bottom sliver, so its presence never
    // changes the card's height.
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => _open(context, title),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: _kPosterAspect,
                child: LayoutBuilder(
                  builder: (context, box) => XpBevel(
                    raised: _hover && !unavailable,
                    color: Xp.well,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (art != null && File(art).existsSync())
                          // cover, not contain: FILL the 2:3 box (no gaps),
                          // cropping whichever dimension overflows.
                          Image.file(File(art), fit: BoxFit.cover)
                        else
                          Center(
                            // A pending placeholder reads as "identifying", not
                            // a broken image (it has no art yet, by design).
                            child: Icon(
                              series.pending
                                  ? Icons.hourglass_empty
                                  : Icons.image_not_supported,
                              color: Xp.textFaint,
                            ),
                          ),
                        if (unavailable)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            // Amber = status (the drive is disconnected, not
                            // broken) — the panel's reserved attention color.
                            child: const Icon(
                              Icons.link_off,
                              color: Xp.warning,
                              size: 32,
                            ),
                          ),
                        if (next != null && !unavailable)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            // ~1/10th of the poster, but never below a legible
                            // floor so the label reads on the smallest tiles.
                            height: math.max(
                              _kNextStripMinHeight,
                              box.maxHeight * 0.1,
                            ),
                            child: _NextStrip(
                              number: next.number,
                              onPlay: () async {
                                await widget.onPlay(next, series);
                                widget.onReturn();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: _kCardTextRegion,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always a two-line-tall block (a one-line title leaves
                      // its second line empty) so the meta line below is pinned
                      // to the same Y on every card.
                      SizedBox(
                        height: _kTitleBlockHeight,
                        width: double.infinity,
                        // Show title as a CHROME label — the thin tracked matte
                        // caps used for "Continue watching" / "Settings". Keeps
                        // the card's fixed font size + line height so the 2-line
                        // title block stays uniform across cards.
                        child: ChromeLabel(
                          title,
                          upper: false,
                          maxLines: 2,
                          fontSize: _kCardTitleFontSize,
                          height: _kCardTitleLineHeight,
                          letterSpacing: 1,
                          color: _hover && !unavailable
                              ? Xp.accentBright
                              : Xp.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _metaLine(series, unavailable),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimum height (logical px) of the overlaid "Next" footer strip, so its label
/// stays legible even when 1/10th of a small poster would be thinner.
const double _kNextStripMinHeight = 22;

/// The "Next: Ep N" affordance: a beveled footer strip seated on the bottom
/// sliver of a card's poster. It reads as an integrated part of the card (a
/// bottom "seat"), styled from the same tokens as [XpButton] — NOT a floating
/// Material button. Its own tap plays the next episode; because it's a nested
/// [GestureDetector], the tap wins the gesture arena and does NOT bubble to the
/// card's open-detail tap (the same control-vs-parent pattern the player uses).
class _NextStrip extends StatefulWidget {
  const _NextStrip({required this.number, required this.onPlay});

  final int number;
  final Future<void> Function() onPlay;

  @override
  State<_NextStrip> createState() => _NextStripState();
}

class _NextStripState extends State<_NextStrip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onPlay,
        child: XpBevel(
          raised: !pressed,
          gradient: Xp.controlGradient(hover: _hover),
          child: Transform.translate(
            offset: pressed ? const Offset(1, 1) : Offset.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow, size: 14, color: Xp.text),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Next: Ep ${widget.number}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Xp.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
