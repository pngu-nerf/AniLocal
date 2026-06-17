import 'package:flutter/material.dart';

import '../../../domain/models/episode.dart';
import '../theater_widgets.dart';

/// The EPISODE-LIST zone: an independently scrollable list of the series'
/// episodes. Tapping one asks the host to swap the video in place (no
/// navigation) via [onSelect]; the currently-playing episode is marked.
///
/// Position-agnostic: it fills the box the layout gives it and scrolls within
/// it. Handles a few episodes (short list, no scroll) and many (scrolls, and
/// auto-scrolls to keep the now-playing episode in view). No width or position
/// is baked in here.
class EpisodeListZone extends StatefulWidget {
  const EpisodeListZone({
    super.key,
    required this.episodes,
    required this.current,
    required this.onSelect,
  });

  final List<Episode> episodes;

  /// The episode currently playing in the video zone (marked "now playing").
  final Episode current;

  final ValueChanged<Episode> onSelect;

  @override
  State<EpisodeListZone> createState() => _EpisodeListZoneState();
}

class _EpisodeListZoneState extends State<EpisodeListZone> {
  final _scroll = ScrollController();
  static const double _rowExtent = 64;

  static bool _isCurrent(Episode a, Episode b) =>
      a.seriesAnilistId == b.seriesAnilistId &&
      a.anchoredNumber == b.anchoredNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(EpisodeListZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isCurrent(widget.current, oldWidget.current)) _scrollToCurrent();
  }

  /// Keep the now-playing episode visible as it changes (incl. auto-advance).
  void _scrollToCurrent() {
    if (!_scroll.hasClients) return;
    final i = widget.episodes.indexWhere((e) => _isCurrent(e, widget.current));
    if (i < 0) return;
    final target = (i * _rowExtent).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZoneEyebrow(label: 'Episodes', trailing: '${widget.episodes.length}'),
          const Divider(height: 1),
          Expanded(
            child: widget.episodes.isEmpty
                ? const _EmptyEpisodes()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemExtent: _rowExtent,
                    itemCount: widget.episodes.length,
                    itemBuilder: (context, i) {
                      final e = widget.episodes[i];
                      return _EpisodeTile(
                        episode: e,
                        current: _isCurrent(e, widget.current),
                        onTap: () => widget.onSelect(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.current,
    required this.onTap,
  });

  final Episode episode;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = episode.duration > Duration.zero
        ? episode.resumePosition.inMilliseconds /
              episode.duration.inMilliseconds
        : 0.0;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: current ? scheme.primaryContainer : Colors.transparent,
          // The "selected seat": a primary accent bar on the now-playing row.
          border: Border(
            left: BorderSide(
              color: current ? scheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _NumberChip(number: episode.number, active: current),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title ?? 'Episode ${episode.number}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color: current
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  if (!episode.watched &&
                      episode.resumePosition > Duration.zero)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (episode.watched)
              Icon(Icons.check_circle, size: 16, color: scheme.primary)
            else if (current)
              Icon(Icons.volume_up, size: 16, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

/// Leading episode-number chip. Numbering is a real sequence here, so it earns
/// its place as the row's structural marker.
class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.number, required this.active});

  final int number;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w700,
          color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyEpisodes extends StatelessWidget {
  const _EmptyEpisodes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No episodes here yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
