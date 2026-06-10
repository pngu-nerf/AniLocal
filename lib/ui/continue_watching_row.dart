import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/continue_watching.dart';

/// Horizontal "Continue watching" row: in-progress episodes with a resume
/// progress bar. Tapping an entry resumes playback.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.entries,
    required this.onPlay,
    required this.onDismiss,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final List<ContinueWatching> entries;
  final Future<void> Function(ContinueWatching) onPlay;
  final Future<void> Function(ContinueWatching) onDismiss;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggleCollapsed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text(
                  'Continue watching',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        if (!collapsed)
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _Card(
                entry: entries[i],
                onPlay: onPlay,
                onDismiss: onDismiss,
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.entry,
    required this.onPlay,
    required this.onDismiss,
  });

  final ContinueWatching entry;
  final Future<void> Function(ContinueWatching) onPlay;
  final Future<void> Function(ContinueWatching) onDismiss;

  @override
  Widget build(BuildContext context) {
    final ep = entry.episode;
    final art = entry.series.coverImageRef;
    final total = ep.duration.inMilliseconds;
    final progress = total > 0 ? ep.resumePosition.inMilliseconds / total : 0.0;
    final title =
        entry.series.titles.english ??
        entry.series.titles.romaji ??
        entry.series.titles.native ??
        '#${entry.series.anilistId}';

    return InkWell(
      onTap: () => onPlay(entry),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (art != null && File(art).existsSync())
                          ? Image.file(File(art), fit: BoxFit.cover, width: 110)
                          : Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.play_arrow),
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => onDismiss(entry),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Text(
              'Episode ${ep.number}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
