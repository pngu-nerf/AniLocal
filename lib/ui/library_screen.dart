import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/series.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/library_repository.dart';
import 'series_detail_screen.dart';
import 'unmatched_screen.dart';

/// Stage 4 home: browse the cached library. Reads ONLY from the repository
/// (cache) — instant and offline. The scan/refresh action triggers the fill
/// path via [onScan]; the UI never imports sync/cache/AniList types (seam #1).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.onScan,
  });

  final LibraryRepository repository;
  final Future<SyncSummary> Function() onScan;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<Series>> _series;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _series = widget.repository.allSeries();
    });
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final summary = await widget.onScan();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_summaryText(summary))));
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
            icon: const Icon(Icons.help_outline),
            tooltip: 'Unmatched files',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UnmatchedScreen(repository: widget.repository),
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
      body: FutureBuilder<List<Series>>(
        future: _series,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final series = snapshot.data ?? const [];
          if (series.isEmpty) {
            return const Center(
              child: Text('No library yet — tap the refresh icon to scan.'),
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
            itemBuilder: (_, i) =>
                _SeriesCard(series: series[i], repository: widget.repository),
          );
        },
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.repository});

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
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SeriesDetailScreen(series: series, repository: repository),
        ),
      ),
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
