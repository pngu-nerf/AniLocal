import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

import '../../domain/models/episode.dart';
import '../../domain/models/series.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/watch_order_repository.dart';
import '../../domain/repositories/watch_state_repository.dart';
import '../theme/header_readout.dart';
import '../window_chrome.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/header_actions.dart';
import 'theater_layout.dart';
import 'theater_layout_config.dart';
import 'zones/episode_list_zone.dart';
import 'zones/series_info_zone.dart';
import 'zones/video_zone.dart';
import '../../playback/playback_controller.dart';

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
    required this.playback,
    required this.settings,
    required this.unmatchedCount,
    required this.onFolders,
    required this.onScan,
    required this.onUnmatched,
    required this.onSettings,
    this.config = TheaterLayoutConfig.theaterDefault,
  });

  final Series series;
  final Episode initialEpisode;
  final LibraryRepository repository;
  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// The app-lifetime playback engine (composition root), handed to the
  /// VideoZone. The theater CONSUMES it; popping this route stops playback
  /// but leaves the engine alive.
  final PlaybackController playback;

  /// ALL app-wide settings behind ONE injected object — the theater reads the
  /// player prefs (auto-play / skip / watched-threshold, forwarded to VideoZone)
  /// and the persisted rail-width fraction from it.
  final SettingsRepository settings;

  /// The shared header actions (Sources / Sync / Unmatched / Settings), forwarded
  /// from the launching screen so the theater header is IDENTICAL to home/detail
  /// — same [HeaderActionsBar], only the back button differs. Sync runs quietly
  /// here (no local spinner), like the detail screen.
  final int unmatchedCount;
  final Future<void> Function() onFolders;
  final Future<void> Function() onScan;
  final VoidCallback onUnmatched;
  final VoidCallback onSettings;

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

  /// FULLSCREEN IS STATE. Not a route — this single bool is the whole mode.
  ///
  /// media_kit's `toggleFullscreen(context)` used to push a root-navigator route
  /// holding a SECOND Video over the SAME VideoState, whose duplicated inherited
  /// widgets are what tripped `_dependents.isEmpty` on the way back out. Nothing
  /// pushes or pops now.
  ///
  /// **MIRRORED FROM THE WINDOW, never predicted.** This is set only from
  /// [WindowChrome.fullscreen] — the `NSWindowDidEnter/ExitFullScreen` signal —
  /// so the layout changes when the window has ACTUALLY changed. Flipping it
  /// next to the native call (what this used to do) repainted the new layout a
  /// frame or two before the window resized, which read as a two-step
  /// transition, and it went stale whenever the OS drove the change instead of
  /// us (green traffic light, Ctrl-Cmd-F).
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialEpisode;
    _railFraction = widget.config.railFraction;
    // Follow the REAL window state. Seeded from it too, so entering the theater
    // while the window is already fullscreen renders correctly on frame one.
    _fullscreen = WindowChrome.fullscreen.value;
    WindowChrome.fullscreen.addListener(_onWindowFullscreenChanged);
    _loadRailFraction();
    _loadEpisodes();
  }

  @override
  void dispose() {
    WindowChrome.fullscreen.removeListener(_onWindowFullscreenChanged);
    super.dispose();
  }

  /// The window finished entering or leaving fullscreen — from ANY cause (our
  /// ⛶ / Escape, the green traffic light, Ctrl-Cmd-F, Mission Control). One
  /// path for all of them, which is what keeps OS-initiated changes in sync.
  void _onWindowFullscreenChanged() {
    if (!mounted) return;
    setState(() => _fullscreen = WindowChrome.fullscreen.value);
  }

  Future<void> _loadRailFraction() async {
    final stored = await widget.settings.loadRailFraction();
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

  /// Enter/exit fullscreen. The ONE fullscreen path — the ⛶ button and the
  /// Escape shortcut both land here via [PlayerControlsActions.toggleFullscreen].
  ///
  /// Two separable things, which media_kit bundled into one route push and we
  /// keep apart:
  ///  1. LAYOUT — [_fullscreen] drives the layout config (video only, chrome
  ///     hidden). Pure setState; the widget tree keeps its shape so the video
  ///     zone is never rebuilt (see TheaterLayout's shape-invariance note).
  ///  2. THE OS WINDOW — the publicly-overridable native hooks media_kit exposes
  ///     (a MethodChannel `Utils.Enter/ExitNativeFullscreen` on desktop). Same
  ///     native behaviour as before, just called directly instead of as a side
  ///     effect of pushing a route.
  ///
  /// Tooltips are dismissed FIRST, synchronously, before the OS resizes the
  /// window: a tooltip mounted across an overlay-size change is the
  /// `size == theater.size` crash. TooltipDismissOnResize is the general net;
  /// this is the deterministic one for the path we control.
  void _toggleFullscreen() {
    // Ask the OS, then wait to be told. No optimistic setState: the layout must
    // not move until the window has, or the intermediate frame shows the wrong
    // layout at the wrong size (the two-step exit). The reply arrives on
    // WindowChrome.fullscreen -> _onWindowFullscreenChanged.
    Tooltip.dismissAllToolTips();
    if (_fullscreen) {
      defaultExitNativeFullscreen();
    } else {
      defaultEnterNativeFullscreen();
    }
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
    final title = widget.series.displayTitle;

    final episodes = _episodes ?? const <Episode>[];

    final zones = <TheaterZone, Widget>{
      TheaterZone.video: VideoZone(
        // Keyed by series so a different show gets a fresh playback frame;
        // within a series, the same frame swaps episodes in place.
        key: ValueKey(widget.series.anilistId),
        episode: _current,
        watchState: widget.watchState,
        watchOrder: widget.watchOrder,
        playback: widget.playback,
        settings: widget.settings,
        fullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
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

    // FULLSCREEN IS JUST A CONFIG. Video only, rail + info hidden — exactly the
    // "hide a zone is a config change" seam TheaterLayoutConfig was built for.
    // The zone WIDGETS are identical in both modes (same map, same instances),
    // and the layout is shape-invariant, so toggling repositions the video
    // rather than rebuilding it.
    final config = _fullscreen
        ? widget.config.copyWith(visibleZones: const {TheaterZone.video})
        : widget.config.copyWith(railFraction: _railFraction);

    return Scaffold(
      // The theater keeps its Material Scaffold and its own SHELL (NOT XpWindow
      // — it's a pushed route, not the root window frame, and re-shelling it
      // would drag in the fullscreen/focus/cursor machinery: see
      // docs/header-architecture-audit.md). Only the shell differs. The header
      // itself is the SAME XpTitleBar every other screen uses, in its standard
      // layout — serif brand mark, window-centred VFD screen, the same
      // label/abbreviation collapse — so the player's chrome reads identically
      // to the rest of the app.
      //
      // Hidden in fullscreen: no header at all. Scaffold slots its children by
      // id, so dropping the appBar does not disturb the body's element — the
      // video keeps playing straight through the toggle.
      appBar: _fullscreen
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(Xp.titleBarHeight),
              child: XpTitleBar(
                caption: title,
                captionWidget: HeaderReadout(title: title),
                leading: XpTitleTab(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  tooltip: 'Back',
                  showLabel: XpTitleBar.showsLabels(context),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                trailing: HeaderActionsBar(
                  // Sync runs quietly from the theater (no local spinner), like detail.
                  scanning: false,
                  unmatchedCount: widget.unmatchedCount,
                  onFolders: widget.onFolders,
                  onScan: widget.onScan,
                  onUnmatched: widget.onUnmatched,
                  onSettings: widget.onSettings,
                ),
              ),
            ),
      body: TheaterLayout(
        config: config,
        zones: zones,
        // The rail is always resizable (settings persists its width); live-drag
        // updates the fraction, drag-end persists it. No rail in fullscreen, so
        // no divider either.
        onRailResize: _fullscreen
            ? null
            : (f) => setState(() => _railFraction = f),
        onRailResizeEnd: _fullscreen
            ? null
            : () => widget.settings.setRailFraction(_railFraction),
      ),
    );
  }
}
