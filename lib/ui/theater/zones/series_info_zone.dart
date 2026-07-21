import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/models/series.dart';
import '../../theme/xp_widgets.dart';
import '../theater_widgets.dart';

/// The SERIES-INFO zone: cover, title, episode count, and the existing
/// metadata, plus the episode currently playing. Sits below the video.
///
/// Position-agnostic and sizes to its CONTENT (it does NOT fill or scroll), so
/// the left column has no dead whitespace beneath it. If its box is ever shorter
/// than the content (a very short window) it clips/caps rather than overflowing.
/// No width/position is hardcoded here.
class SeriesInfoZone extends StatelessWidget {
  const SeriesInfoZone({
    super.key,
    required this.series,
    required this.episodeCount,
    required this.nowPlaying,
  });

  final Series series;

  /// Episodes actually in the library for this series (falls back to AniList's
  /// reported count for the headline figure).
  final int episodeCount;

  /// The episode currently in the video frame.
  final Episode nowPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        'Untitled';
    final art = series.coverImageRef;

    final meta = <String>[
      if (series.format != null) series.format!,
      '${series.episodeCount ?? episodeCount} episodes',
      if (!series.pending) 'AniList #${series.anilistId}',
    ];

    // Sizes to its CONTENT (mainAxisSize.min) — no greedy scroll view, so the
    // left column has no dead whitespace below the info. No scroll. ClipRect is
    // the graceful-degradation guard: if a window is so short that the content
    // can't fit the column, it's clipped (capped) instead of overflowing —
    // never the case at normal sizes (this content is short).
    return Material(
      color: scheme.surfaceContainerLow,
      child: ClipRect(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZoneEyebrow(label: 'Now playing'),
              // Episode title as a CHROME label (thin tracked matte caps).
              ChromeLabel(
                nowPlaying.title ?? 'Episode ${nowPlaying.number}',
                upper: false,
                fontSize: 15,
                letterSpacing: 1.2,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(art: art, pending: series.pending),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Series title as a CHROME label (thin tracked caps).
                        ChromeLabel(
                          title,
                          upper: false,
                          fontSize: 20,
                          maxLines: 2,
                          letterSpacing: 1.2,
                        ),
                        if (series.titles.native != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            series.titles.native!,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          series.pending ? 'Identifying…' : meta.join('  ·  '),
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover art at a fixed 2:3 poster ratio. A pending placeholder shows a quiet
/// "identifying" tile rather than a broken image.
class _Cover extends StatelessWidget {
  const _Cover({required this.art, required this.pending});

  final String? art;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 92,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: (art != null && File(art!).existsSync())
              ? Image.file(File(art!), fit: BoxFit.cover)
              : ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    pending ? Icons.hourglass_empty : Icons.movie_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
