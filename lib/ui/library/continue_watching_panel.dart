import 'package:flutter/material.dart';

import '../../domain/models/continue_watching.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/show_cover.dart';

/// Vertical "Continue watching" side panel: in-progress episodes with a resume
/// progress bar, newest first. Tapping an entry resumes playback; the per-card
/// dismiss clears that entry. Collapsing shrinks it to a thin strip with an
/// expand affordance (the persisted toggle relocated from the old top row).
///
/// Styled as an XP group box (a little window-within-the-window). It fills
/// whatever box `LibraryLayout` hands it — the layout owns the width (full when
/// expanded, a thin strip when collapsed); this only swaps header-vs-list.
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
    return XpGroupBox(
      title: 'Continue watching',
      trailing: XpButton(
        dense: true,
        icon: Icons.chevron_left,
        tooltip: 'Collapse',
        onPressed: onToggleCollapsed,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(6),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) =>
            _Card(entry: entries[i], onPlay: onPlay, onDismiss: onDismiss),
      ),
    );
  }

  /// Collapsed strip: just the expand affordance, with a vertical label so the
  /// panel is still discoverable when narrowed.
  Widget _collapsed(BuildContext context) {
    return XpPanel(
      color: Xp.surface,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onToggleCollapsed,
        child: Column(
          children: [
            XpButton(
              dense: true,
              icon: Icons.chevron_right,
              tooltip: 'Show continue watching',
              onPressed: onToggleCollapsed,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text(
                    'Continue watching',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Xp.textDim),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One in-progress entry as a compact raised tile (sunken poster thumbnail +
/// title + episode + resume bar), sized for the narrow vertical panel.
class _Card extends StatelessWidget {
  const _Card({
    required this.entry,
    required this.onPlay,
    required this.onDismiss,
  });

  final ContinueWatching entry;
  final Future<void> Function(ContinueWatching) onPlay;
  final Future<void> Function(ContinueWatching) onDismiss;

  /// Clock string for [d], rounded to the nearest second: `m:ss`, widening to
  /// `h:mm:ss` once it's an hour or more (so 90 min reads `1:30:00`, not
  /// `90:00`). Each value is formatted by its own magnitude, media-player style.
  static String _clock(Duration d) {
    final totalSeconds = (d.inMilliseconds / 1000).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final ep = entry.episode;
    final art = entry.series.coverImageRef;
    final total = ep.duration.inMilliseconds;
    final progress = total > 0 ? ep.resumePosition.inMilliseconds / total : 0.0;
    // Text mirrors the SAME two values the bar above reads — no re-fetch, no
    // recompute — so the label and the bar can never disagree.
    final percent = (progress * 100).round();
    final title = entry.series.displayTitle;

    return MouseRegion(
      // The whole tile resumes playback on tap → show the click affordance.
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onPlay(entry),
        child: XpPanel(
          color: Xp.surfaceAlt,
          padding: const EdgeInsets.all(6),
          // The panel width is user-draggable (a fraction of the page), so a card
          // can get narrow. Below a threshold, drop the poster thumbnail so the
          // text + dismiss button always fit — no overflow at any panel width.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showThumb = constraints.maxWidth >= 120;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showThumb) ...[
                    XpBevel(
                      raised: false,
                      color: Xp.well,
                      child: SizedBox(
                        width: 42,
                        height: 60,
                        // Same shared picture-state renderer the grid / detail /
                        // player use — so blur / remove apply here too, via the
                        // per-show mode carried on entry.series (no parallel path).
                        child: ShowCover(
                          imagePath: art,
                          pictureMode: entry.series.pictureMode,
                          placeholderIcon: Icons.play_arrow,
                          iconSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show title as a CHROME label (thin tracked matte
                        // caps), matching the grid card and section headers.
                        ChromeLabel(
                          title,
                          upper: false,
                          maxLines: 2,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Episode ${ep.number}',
                          style: const TextStyle(
                            color: Xp.textDim,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        XpBevel(
                          raised: false,
                          color: Xp.well,
                          child: SizedBox(
                            height: 8,
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              backgroundColor: Xp.well,
                              color: Xp.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_clock(ep.resumePosition)} / '
                          '${_clock(ep.duration)} ~ $percent%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Xp.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  XpButton(
                    dense: true,
                    icon: Icons.close,
                    tooltip: 'Remove from continue watching',
                    onPressed: () => onDismiss(entry),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
