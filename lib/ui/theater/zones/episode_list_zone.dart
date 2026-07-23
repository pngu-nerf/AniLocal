import 'package:flutter/material.dart';

import '../../../domain/models/episode.dart';
import '../../theme/xp_tokens.dart';
import '../../widgets/episode_tile.dart';
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
    return Material(
      // True-black display field — the rail reads as a lit panel, matching the
      // detail-page episode list.
      color: Xp.well,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZoneEyebrow(label: 'Episodes', trailing: '${widget.episodes.length}'),
          const Divider(height: 1, color: Xp.divider),
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
                      final resuming =
                          !e.watched && e.resumePosition > Duration.zero;
                      final progress = e.duration > Duration.zero
                          ? e.resumePosition.inMilliseconds /
                                e.duration.inMilliseconds
                          : 0.0;
                      final current = _isCurrent(e, widget.current);
                      // Shared tile; the rail turns ON the now-playing highlight
                      // and passes a resume-progress bar as the detail slot.
                      return EpisodeTile(
                        number: e.number,
                        title: e.title ?? 'Episode ${e.number}',
                        active: current,
                        nowPlaying: true,
                        onTap: () => widget.onSelect(e),
                        detail: resuming
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  minHeight: 3,
                                  color: Xp.accent,
                                  backgroundColor: Xp.surfaceAlt,
                                ),
                              )
                            : null,
                        trailing: [
                          if (e.watched)
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Xp.accent,
                            )
                          else if (current)
                            const Icon(
                              Icons.volume_up,
                              size: 16,
                              color: Xp.accentBright,
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
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
