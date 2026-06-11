import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/episode.dart';
import '../domain/models/episode_source.dart';
import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'fix_match_screen.dart';
import 'player_screen.dart';

/// Series detail: cover + metadata + the episodes (matched files) for this
/// series. Each episode can be reassigned, or used as a season-split point.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.loadAutoPlayNext,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;
  final Future<bool> Function() loadAutoPlayNext;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Future<List<Episode>> _episodes;
  Episode? _next; // next episode to watch for this series (relations-aware)

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _episodes = widget.repository.episodesFor(widget.series.anilistId);
    });
    widget.watchOrder.upNextBySeries().then((m) {
      if (mounted) setState(() => _next = m[widget.series.anilistId]);
    });
  }

  String get _query =>
      widget.series.titles.romaji ??
      widget.series.titles.english ??
      widget.series.titles.native ??
      '';

  Future<void> _play(Episode e) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          episode: e,
          watchState: widget.watchState,
          watchOrder: widget.watchOrder,
          autoPlayEnabled: widget.loadAutoPlayNext,
        ),
      ),
    );
    _reload(); // reflect updated watched / resume position / up-next
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _reassignOne(Episode e) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: [e.fileRef],
          prefillQuery: _query,
        ),
      ),
    );
    if (done == true) _reload();
  }

  static String _name(String path) => path.split(Platform.pathSeparator).last;

  /// Pick which source a multi-source episode plays from: "Automatic" (folder
  /// priority — the default) or a specific copy (a manual pin that survives
  /// rescans). Switching only changes which file opens — nothing on disk moves.
  Future<void> _chooseSource(Episode e) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final priorityDefault = e.sources.first; // sources are priority-ordered
        return AlertDialog(
          title: Text('Episode ${e.number} — source'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    e.pinnedSourceFolder == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: const Text('Automatic (highest priority)'),
                  subtitle: Text('Plays from ${priorityDefault.fileRef}'),
                  onTap: () async {
                    await widget.sourceSelection.clearSource(e);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
                const Divider(height: 1),
                for (final EpisodeSource s in e.sources)
                  ListTile(
                    leading: Icon(
                      e.pinnedSourceFolder == s.folderPath
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(s.fileRef),
                    subtitle: s == priorityDefault
                        ? const Text('default')
                        : null,
                    onTap: () async {
                      await widget.sourceSelection.selectSource(
                        e,
                        folderPath: s.folderPath,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    if (changed == true) _reload();
  }

  Future<void> _splitFromHere(List<Episode> all, int index) async {
    final range = all.sublist(index).map((e) => e.fileRef).toList();
    // Real prior-season count: this series' AniList episode count (fallback to
    // the split point minus one). Never hardcoded.
    final prior = widget.series.episodeCount ?? (all[index].number - 1);
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: range,
          prefillQuery: _query,
          isSplit: true,
          priorEpisodeCount: prior,
        ),
      ),
    );
    if (done == true) _reload();
  }

  Widget _episodeTile(List<Episode> episodes, int i) {
    final e = episodes[i];
    final multi = e.hasMultipleSources;
    return ListTile(
      dense: true,
      onTap: () => _play(e),
      leading: CircleAvatar(child: Text('${e.number}')),
      title: Text(e.title ?? 'Episode ${e.number}'),
      subtitle: Text(
        [
          _name(e.fileRef),
          if (multi) '${e.sources.length} sources · from ${e.fileRef}',
          if (!e.watched && e.resumePosition > Duration.zero)
            '▸ resume ${_fmt(e.resumePosition)}',
        ].join('\n'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (e.watched)
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (multi)
            IconButton(
              tooltip: '${e.sources.length} sources — choose…',
              icon: Badge(
                label: Text('${e.sources.length}'),
                child: const Icon(Icons.layers_outlined),
              ),
              onPressed: () => _chooseSource(e),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reassign') _reassignOne(e);
              if (v == 'split') _splitFromHere(episodes, i);
              if (v == 'source') _chooseSource(e);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reassign',
                child: Text('Reassign this episode…'),
              ),
              const PopupMenuItem(
                value: 'split',
                child: Text('Split: reassign from here…'),
              ),
              if (multi)
                const PopupMenuItem(
                  value: 'source',
                  child: Text('Choose source…'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<Episode>>(
        future: _episodes,
        builder: (context, snapshot) {
          final episodes = snapshot.data ?? const <Episode>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (art != null && File(art).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(art),
                        width: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (series.titles.romaji != null)
                          Text(series.titles.romaji!),
                        if (series.titles.native != null)
                          Text(series.titles.native!),
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (series.format != null) series.format,
                            if (series.episodeCount != null)
                              '${series.episodeCount} episodes',
                            'AniList #${series.anilistId}',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_next != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => _play(_next!),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _next!.seriesAnilistId == series.anilistId
                          ? 'Play next: Episode ${_next!.number}'
                          : 'Play next: Episode ${_next!.number} (sequel)',
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Episodes (in library)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (var i = 0; i < episodes.length; i++)
                  _episodeTile(episodes, i),
            ],
          );
        },
      ),
    );
  }
}
