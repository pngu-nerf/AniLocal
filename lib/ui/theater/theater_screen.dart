import 'package:flutter/material.dart';

import '../../domain/models/episode.dart';
import '../../domain/models/series.dart';
import '../../domain/models/skip_mode.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/watch_order_repository.dart';
import '../../domain/repositories/watch_state_repository.dart';
import 'theater_layout.dart';
import 'theater_layout_config.dart';
import 'zones/episode_list_zone.dart';
import 'zones/series_info_zone.dart';
import 'zones/video_zone.dart';

/// The theater watch screen: video, episode list, and series info as three
/// self-contained zones arranged by [TheaterLayout] from a [TheaterLayoutConfig].
///
/// This screen only ASSEMBLES — it builds each zone with its data and hands the
/// set to the layout. It owns one piece of shared state, [_current] (the
/// episode in the video frame): the list selects into it (swap in place, no
/// navigation) and the video reports auto-advance back into it. It holds no
/// geometry; repositioning is entirely a [TheaterLayoutConfig] concern.
class TheaterScreen extends StatefulWidget {
  const TheaterScreen({
    super.key,
    required this.series,
    required this.initialEpisode,
    required this.repository,
    required this.watchState,
    required this.watchOrder,
    required this.loadAutoPlayNext,
    required this.loadSkipMode,
    this.loadRailFraction,
    this.setRailFraction,
    this.config = TheaterLayoutConfig.theaterDefault,
  });

  final Series series;
  final Episode initialEpisode;
  final LibraryRepository repository;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;
  final Future<bool> Function() loadAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;

  /// Persisted rail width (fraction of total). When [loadRailFraction] is
  /// supplied the rail gets a draggable divider and remembers its width across
  /// launches; null → a fixed rail at [config]'s fraction (no divider).
  final Future<double> Function()? loadRailFraction;
  final Future<void> Function(double fraction)? setRailFraction;

  /// The arrangement. Defaults to the YouTube-style theater; a future Settings
  /// or drag-to-resize just supplies a different config — the zones are unchanged.
  final TheaterLayoutConfig config;

  @override
  State<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends State<TheaterScreen> {
  late Episode _current;
  List<Episode>? _episodes; // null while first loading

  /// Live rail width. Seeded from the config so the first frame is correct,
  /// then overwritten by the persisted value (clamped) once it loads.
  late double _railFraction;

  @override
  void initState() {
    super.initState();
    _current = widget.initialEpisode;
    _railFraction = widget.config.railFraction;
    _loadRailFraction();
    _loadEpisodes();
  }

  Future<void> _loadRailFraction() async {
    final load = widget.loadRailFraction;
    if (load == null) return;
    final stored = await load();
    final clamped = stored.clamp(
      TheaterLayoutConfig.railFractionMin,
      TheaterLayoutConfig.railFractionMax,
    );
    if (mounted) setState(() => _railFraction = clamped);
  }

  Future<void> _loadEpisodes() async {
    final eps = await widget.repository.episodesFor(widget.series.anilistId);
    if (mounted) setState(() => _episodes = eps);
  }

  /// The host-driven swap (a list tap): point the video at [episode]. The
  /// VideoZone re-opens it in place — no navigation.
  void _select(Episode episode) {
    if (episode.anchoredNumber == _current.anchoredNumber) return;
    setState(() => _current = episode);
  }

  /// The video advanced itself (auto-play). Follow it, and refresh the list so
  /// the just-finished episode picks up its watched mark.
  void _onAdvanced(Episode episode) {
    setState(() => _current = episode);
    _loadEpisodes();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.series.titles.english ??
        widget.series.titles.romaji ??
        widget.series.titles.native ??
        'Theater';

    final episodes = _episodes ?? const <Episode>[];

    final zones = <TheaterZone, Widget>{
      TheaterZone.video: VideoZone(
        // Keyed by series so a different show gets a fresh playback frame;
        // within a series, the same frame swaps episodes in place.
        key: ValueKey(widget.series.anilistId),
        episode: _current,
        watchState: widget.watchState,
        watchOrder: widget.watchOrder,
        autoPlayEnabled: widget.loadAutoPlayNext,
        skipMode: widget.loadSkipMode,
        onEpisodeChanged: _onAdvanced,
      ),
      TheaterZone.seriesInfo: SeriesInfoZone(
        series: widget.series,
        episodeCount: episodes.length,
        nowPlaying: _current,
      ),
      TheaterZone.episodeList: EpisodeListZone(
        episodes: episodes,
        current: _current,
        onSelect: _select,
      ),
    };

    // Resizing is enabled only when a persistence hook is wired; without it the
    // rail stays a fixed fraction (no divider).
    final resizable = widget.loadRailFraction != null;
    final config = widget.config.copyWith(railFraction: _railFraction);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: TheaterLayout(
        config: config,
        zones: zones,
        onRailResize: resizable
            ? (f) => setState(() => _railFraction = f)
            : null,
        onRailResizeEnd: resizable
            ? () => widget.setRailFraction?.call(_railFraction)
            : null,
      ),
    );
  }
}
