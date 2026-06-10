import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/continue_watching.dart';
import '../domain/models/series.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'access_recovery.dart';
import 'continue_watching_row.dart';
import 'folders_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';
import 'unmatched_screen.dart';

/// Stage 4/5 home: browse the cached library. Reads ONLY from the repository
/// (cache) — instant and offline. Scan (fill path) and add-folder (native
/// picker) are injected callbacks; the UI never imports sync/cache/picker types.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.onScan,
    required this.onAddFolder,
    required this.accessIssues,
    required this.onOpenAccessSettings,
    required this.loadContinueCollapsed,
    required this.setContinueCollapsed,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final Future<SyncSummary> Function() onScan;

  /// Load/persist the collapsed state of the "Continue watching" section.
  final Future<bool> Function() loadContinueCollapsed;
  final Future<void> Function(bool collapsed) setContinueCollapsed;

  /// Opens the native folder picker; reports whether a folder was added and the
  /// denied TCC category label (if the folder's category access was refused).
  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  /// Shared denied-state (category labels) — drives the banner; the add-dialog
  /// reads the same source via [onAddFolder]'s result.
  final ValueListenable<List<String>> accessIssues;
  final Future<bool> Function() onOpenAccessSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<Series>> _series;
  late Future<List<ContinueWatching>> _continue;
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
  }

  Future<void> _playFromContinue(ContinueWatching entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlayerScreen(episode: entry.episode, watchState: widget.watchState),
      ),
    );
    _reload(); // progress/watched may have changed
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
              // however the screen was closed.
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
        ],
      ),
      body: Column(
        children: [
          // Ambient access-recovery banner (shared denied-state).
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
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: series.length,
                  itemBuilder: (_, i) => _SeriesCard(
                    series: series[i],
                    repository: widget.repository,
                    fixMatch: widget.fixMatch,
                    watchState: widget.watchState,
                    onReturn: _reload,
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
    required this.onReturn,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SeriesDetailScreen(
              series: series,
              repository: repository,
              fixMatch: fixMatch,
              watchState: watchState,
            ),
          ),
        );
        onReturn(); // continue-watching may have changed
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (art != null && File(art).existsSync())
                  ? Image.file(
                      File(art),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.image_not_supported),
                      ),
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
            [
              if (series.format != null) series.format,
              if (series.episodeCount != null) '${series.episodeCount} ep',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
