import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/continue_watching.dart';

/// Vertical "Continue watching" side panel: in-progress episodes with a resume
/// progress bar, newest first. Tapping an entry resumes playback; the per-card
/// dismiss clears that entry. Collapsing shrinks it to a thin strip with an
/// expand affordance (the persisted toggle relocated from the old top row).
///
/// Geometry-agnostic: it fills whatever box `LibraryLayout` hands it (the
/// layout owns the width — full panel when expanded, a thin strip when
/// collapsed). It only renders header-vs-list based on [collapsed].
class ContinueWatchingPanel extends StatelessWidget {
  const ContinueWatchingPanel({
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
    if (collapsed) return _collapsed(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggleCollapsed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Continue watching',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_left, size: 20),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, i) =>
                _Card(entry: entries[i], onPlay: onPlay, onDismiss: onDismiss),
          ),
        ),
      ],
    );
  }

  /// Collapsed strip: just the expand affordance, with a vertical label so the
  /// panel is still discoverable when narrowed.
  Widget _collapsed(BuildContext context) {
    return InkWell(
      onTap: onToggleCollapsed,
      child: Column(
        children: [
          const SizedBox(height: 4),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Show continue watching',
            onPressed: onToggleCollapsed,
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Center(
                child: Text(
                  'Continue watching',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One in-progress entry as a compact horizontal card (poster thumbnail + title
/// + episode + resume bar), sized for the narrow vertical panel.
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 68,
                child: (art != null && File(art).existsSync())
                    ? Image.file(File(art), fit: BoxFit.cover)
                    : Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.play_arrow)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Episode ${ep.number}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove from continue watching',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              onPressed: () => onDismiss(entry),
            ),
          ],
        ),
      ),
    );
  }
}
