import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';

/// Stage 3: display the auto-match results for a scanned folder so they can be
/// eyeballed. Depends only on domain models (seam #1). Wrong matches are
/// expected — confidence is surfaced, not hidden (fix-match is Stage 5).
class ScanResultsScreen extends StatelessWidget {
  const ScanResultsScreen({super.key, required this.resultsFuture});

  final Future<List<IdentifiedEpisode>> resultsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<IdentifiedEpisode>>(
      future: resultsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Scan failed.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }
        final results = snapshot.data!;
        if (results.isEmpty) {
          return const Center(
            child: Text('No video files found in the folder.'),
          );
        }
        return Column(
          children: [
            _Summary(results: results),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _ResultTile(result: results[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.results});

  final List<IdentifiedEpisode> results;

  @override
  Widget build(BuildContext context) {
    int count(MatchConfidence c) =>
        results.where((r) => r.confidence == c).length;
    final matched = results.where((r) => r.series != null).length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        '${results.length} files · $matched matched '
        '(${count(MatchConfidence.high)} high / '
        '${count(MatchConfidence.medium)} med / '
        '${count(MatchConfidence.low)} low) · '
        '${count(MatchConfidence.none)} unmatched',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final IdentifiedEpisode result;

  static const Map<MatchConfidence, Color> _colors = {
    MatchConfidence.high: Colors.green,
    MatchConfidence.medium: Colors.amber,
    MatchConfidence.low: Colors.deepOrange,
    MatchConfidence.none: Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final series = result.series;
    final matchedTitle = series == null
        ? '— no match —'
        : (series.titles.english ??
              series.titles.romaji ??
              series.titles.native ??
              '#${series.anilistId}');
    final ep = result.parsedEpisodeNumber;
    final color = _colors[result.confidence]!;

    return ListTile(
      leading: Tooltip(
        message: 'score ${result.matchScore.toStringAsFixed(2)}',
        child: CircleAvatar(radius: 6, backgroundColor: color),
      ),
      title: Text(
        matchedTitle,
        style: TextStyle(
          fontStyle: series == null ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      subtitle: Text(
        '${result.fileName}\n'
        "parsed: \"${result.parsedTitle}\""
        '${ep != null ? ' · ep $ep' : ''}'
        '${series != null ? ' · AniList #${series.anilistId}' : ''}',
      ),
      isThreeLine: true,
      trailing: Text(
        result.confidence.name,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
