import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import 'fix_match_screen.dart';

/// Series detail: cover + metadata + the episodes (matched files) for this
/// series. Each episode can be reassigned, or used as a season-split point.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.repository,
    required this.fixMatch,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Future<List<Episode>> _episodes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _episodes = widget.repository.episodesFor(widget.series.anilistId);
    });
  }

  String get _query =>
      widget.series.titles.romaji ??
      widget.series.titles.english ??
      widget.series.titles.native ??
      '';

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
              const SizedBox(height: 24),
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
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(child: Text('${episodes[i].number}')),
                    title: Text(
                      episodes[i].title ?? 'Episode ${episodes[i].number}',
                    ),
                    subtitle: Text(
                      episodes[i].fileRef.split(Platform.pathSeparator).last,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'reassign') _reassignOne(episodes[i]);
                        if (v == 'split') _splitFromHere(episodes, i);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'reassign',
                          child: Text('Reassign this episode…'),
                        ),
                        PopupMenuItem(
                          value: 'split',
                          child: Text('Split: reassign from here…'),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
