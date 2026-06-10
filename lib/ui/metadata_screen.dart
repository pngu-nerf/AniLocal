import 'package:flutter/material.dart';

import '../domain/models/series.dart';

/// Stage 2: display AniList metadata + cover art for one hardcoded title.
///
/// Seam #1: this depends only on the domain [Series] (via a [Future]). It does
/// not know AniList exists — online vs offline, network vs cache, are invisible
/// here. The composition root (main.dart) supplies the future.
class MetadataScreen extends StatelessWidget {
  const MetadataScreen({super.key, required this.seriesFuture});

  final Future<Series> seriesFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Series>(
      future: seriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error!);
        }
        return _SeriesView(series: snapshot.data!);
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load metadata.\n\n$error',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class _SeriesView extends StatelessWidget {
  const _SeriesView({required this.series});

  final Series series;

  String get _displayTitle =>
      series.titles.english ??
      series.titles.romaji ??
      series.titles.native ??
      'Untitled (#${series.anilistId})';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (series.coverImageRef != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    series.coverImageRef!,
                    width: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 180,
                      height: 256,
                      child: Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayTitle, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    _Meta(label: 'AniList ID', value: '${series.anilistId}'),
                    if (series.format != null)
                      _Meta(label: 'Format', value: series.format!),
                    if (series.episodeCount != null)
                      _Meta(label: 'Episodes', value: '${series.episodeCount}'),
                    if (series.titles.romaji != null)
                      _Meta(label: 'Romaji', value: series.titles.romaji!),
                    if (series.titles.native != null)
                      _Meta(label: 'Native', value: series.titles.native!),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Relations', style: theme.textTheme.titleMedium),
          const Divider(),
          if (series.relations.isEmpty)
            const Text('None')
          else
            ...series.relations.map(
              (r) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Chip(label: Text(r.relationType)),
                title: Text(
                  r.titles.english ??
                      r.titles.romaji ??
                      r.titles.native ??
                      '#${r.anilistId}',
                ),
                subtitle: r.format != null ? Text(r.format!) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
