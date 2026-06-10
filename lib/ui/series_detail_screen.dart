import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import '../domain/repositories/library_repository.dart';

/// Series detail: cover + metadata + the episodes (matched files) for this
/// series, all read from the cache.
class SeriesDetailScreen extends StatelessWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.repository,
  });

  final Series series;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (art != null && File(art).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(art), width: 150, fit: BoxFit.cover),
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
          FutureBuilder<List<Episode>>(
            future: repository.episodesFor(series.anilistId),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final episodes = snapshot.data ?? const [];
              return Column(
                children: [
                  for (final e in episodes)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text('${e.number}')),
                      title: Text(e.title ?? 'Episode ${e.number}'),
                      subtitle: Text(
                        e.fileRef.split(Platform.pathSeparator).last,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
