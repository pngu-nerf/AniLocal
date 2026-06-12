import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/continue_watching.dart';
import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import '../domain/models/skip_mode.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'access_recovery.dart';
import 'continue_watching_row.dart';
import 'folders_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import 'unmatched_screen.dart';

/// A show is "unavailable" iff it has source folders AND every one of them is
/// currently missing — a single connected source keeps a multi-source show
/// playable, so it stays un-greyed. Pure (UI-layer) so it's unit-testable.
@visibleForTesting
bool seriesUnavailable(Set<String> sourceFolders, Set<String> missingFolders) =>
    sourceFolders.isNotEmpty && sourceFolders.every(missingFolders.contains);

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
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;
  final Future<SyncSummary> Function() onScan;

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
  late Future<List<ContinueWatching>> _continue;
  // anilistId -> the next episode to watch (relations-aware). Loaded async;
  // cards show their "Next" affordance once it arrives.
  Map<int, Episode> _upNext = {};
  // anilistId -> the set of library folders its sources live under. Greying is
  // a pure function of this + the live missing-folder set (recomputed in the
  // grid's ValueListenableBuilder, so toggling missing state needs no re-fetch).
  Map<int, Set<String>> _sourceFoldersBySeries = {};
  bool _scanning = false;
  bool _continueCollapsed = false;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.loadContinueCollapsed().then((c) {
      if (mounted) setState(() => _continueCollapsed = c);
    });
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
      _continue = widget.watchState.continueWatching();
    });
    // "Up Next" per series — resolved off the cache; updates the grid when ready.
    widget.watchOrder.upNextBySeries().then((m) {
      if (mounted) setState(() => _upNext = m);
    });
    _loadSourceFolders();
  }

  /// Map each series to the library folders its sources occupy (for greying).
  /// Reads existing domain state only (episodesFor → sources); a show is later
  /// "unavailable" iff every one of these folders is currently missing.
  Future<void> _loadSourceFolders() async {
    final series = await _series;
    final map = <int, Set<String>>{};
    for (final s in series) {
      final eps = await widget.repository.episodesFor(s.anilistId);
      map[s.anilistId] = {
        for (final e in eps)
          for (final src in e.sources) src.folderPath,
      };
    }
    if (mounted) setState(() => _sourceFoldersBySeries = map);
  }

  Future<void> _play(Episode episode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          episode: episode,
          watchState: widget.watchState,
          watchOrder: widget.watchOrder,
          autoPlayEnabled: widget.loadAutoPlayNext,
          skipMode: widget.loadSkipMode,
        ),
      ),
    );
    _reload(); // progress/watched/up-next may have changed
  }

  Future<void> _playFromContinue(ContinueWatching entry) =>
      _play(entry.episode);

  Future<void> _openSettings() async {
    var enabled = await widget.loadAutoPlayNext();
    var skipMode = await widget.loadSkipMode();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Settings'),
        content: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-play next episode'),
                subtitle: const Text(
                  'When an episode ends, play the next one.',
                ),
                value: enabled,
                onChanged: (v) {
                  setLocal(() => enabled = v);
                  widget.setAutoPlayNext(v);
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Skip intro / outro'),
              ),
              for (final mode in SkipMode.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    mode == skipMode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(_skipModeLabel(mode)),
                  onTap: () {
                    setLocal(() => skipMode = mode);
                    widget.setSkipMode(mode);
                  },
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _refreshMetadata(dialogContext),
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Refresh metadata (idMal + skip data)'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static String _skipModeLabel(SkipMode mode) => switch (mode) {
    SkipMode.off => 'No skip',
    SkipMode.button => 'Skip button',
    SkipMode.auto => 'Auto skip',
  };

  /// Re-fetch metadata + skip data for cached series (no scan, no data loss).
  Future<void> _refreshMetadata(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Refreshing metadata…')));
    try {
      final r = await widget.onRefreshMetadata();
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Refreshed ${r.seriesRefreshed} series · '
              '${r.skipsFetched} skip sets fetched',
            ),
          ),
        );
      _reload();
    } catch (e) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    }
  }

  Future<Set<String>> _folderPaths() async =>
      (await widget.repository.watchedFolders()).map((f) => f.path).toSet();

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final summary = await widget.onScan();
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
      ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AniLocal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Library folders',
            onPressed: () async {
              // If the folder SET actually changed while managing folders,
              // trigger an incremental rescan (existing scan path); a no-op
              // dismissal scans nothing. Compare before/after so it's robust to
              // however the screen was closed. (A pure REORDER leaves the set
              // unchanged — no rescan, but reload below so re-resolved default
              // sources show immediately.)
              final before = await _folderPaths();
              if (!context.mounted) return;
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
                _reload(); // order may have changed — re-resolve sources, no scan
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Unmatched files',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UnmatchedScreen(
                  repository: widget.repository,
                  fixMatch: widget.fixMatch,
                ),
              ),
            ),
          ),
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan / refresh',
              onPressed: _scan,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
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
          // Offline drive/mount banner (reconnect — NOT a permission problem).
          ValueListenableBuilder<List<String>>(
            valueListenable: widget.missingFolders,
            builder: (context, labels, _) => labels.isEmpty
                ? const SizedBox.shrink()
                : ReconnectBanner(
                    labels: labels,
                    onRescan: _scanning ? () {} : _scan,
                  ),
          ),
          // "Continue watching" — in-progress episodes, most recent first.
          FutureBuilder<List<ContinueWatching>>(
            future: _continue,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <ContinueWatching>[];
              if (entries.isEmpty) return const SizedBox.shrink();
              return ContinueWatchingRow(
                entries: entries,
                onPlay: _playFromContinue,
                onDismiss: _dismissFromContinue,
                collapsed: _continueCollapsed,
                onToggleCollapsed: _toggleContinueCollapsed,
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<Series>>(
              future: _series,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final series = snapshot.data ?? const [];
                if (series.isEmpty) {
                  return _EmptyState(
                    scanning: _scanning,
                    onAddFolder: _addFolder,
                  );
                }
                // Greying re-evaluates live with the missing-folder set, using
                // the cached per-series folder map (no re-fetch on toggle).
                return ValueListenableBuilder<Set<String>>(
                  valueListenable: widget.missingFolderPaths,
                  builder: (context, missing, _) => GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
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
                        nextEpisode: _upNext[series[i].anilistId],
                        unavailable: unavailable,
                        onPlay: _play,
                        loadAutoPlayNext: widget.loadAutoPlayNext,
                        loadSkipMode: widget.loadSkipMode,
                        onReturn: _reload,
                      );
                    },
                  ),
                );
              },
            ),
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
          const Text('Your library is empty.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: scanning ? null : onAddFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add your first folder'),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a folder of anime — it scans automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.series,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.nextEpisode,
    required this.unavailable,
    required this.onPlay,
    required this.loadAutoPlayNext,
    required this.loadSkipMode,
    required this.onReturn,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// The next episode to watch for this series (relations-aware), or null when
  /// the series isn't started / has nothing next. Drives the "Next" button.
  final Episode? nextEpisode;

  /// True when every source folder of this show is currently missing (offline
  /// drive/NAS): dimmed + marked, and a tap shows a reconnect hint rather than
  /// opening it. Still listed in place (cached art/metadata shown).
  final bool unavailable;
  final Future<void> Function(Episode) onPlay;
  final Future<bool> Function() loadAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;
    // Dimmed + marked when the show's only sources are on an offline folder.
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: InkWell(
        onTap: () async {
          if (unavailable) {
            // Fail gracefully with a reconnect hint (consistent with the
            // banner) — don't open into a screen that can't play anything.
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
                series: series,
                repository: repository,
                fixMatch: fixMatch,
                watchState: watchState,
                sourceSelection: sourceSelection,
                watchOrder: watchOrder,
                loadAutoPlayNext: loadAutoPlayNext,
                loadSkipMode: loadSkipMode,
              ),
            ),
          );
          onReturn(); // continue-watching / up-next may have changed
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (art != null && File(art).existsSync())
                      Image.file(File(art), fit: BoxFit.cover)
                    else
                      Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.image_not_supported),
                        ),
                      ),
                    if (unavailable)
                      Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.link_off,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              unavailable
                  ? 'Unavailable — not connected'
                  : [
                      if (series.format != null) series.format,
                      if (series.episodeCount != null)
                        '${series.episodeCount} ep',
                    ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (nextEpisode != null && !unavailable)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    await onPlay(nextEpisode!);
                    onReturn();
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: Text('Next: Ep ${nextEpisode!.number}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
