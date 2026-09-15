import 'dart:async';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart'
    show PlayerControlsActions;
import 'package:anilocal/ui/widgets/header_actions.dart' show HeaderActionsBar;
import 'package:flutter/material.dart';

import '../../domain/models/episode.dart';
import '../../domain/models/series.dart';
import '../library_services.dart';
import '../routes.dart';
import '../scan_control.dart';
import '../shell/header_scope.dart';
import '../shell/header_spec.dart';
import '../widgets/guarded.dart';
import '../window_chrome.dart';
import 'theater_layout.dart';
import 'theater_layout_config.dart';
import 'zones/episode_list_zone.dart';
import 'zones/series_info_zone.dart';
import 'zones/video_zone.dart';

/// The theater watch screen: video, episode list, and series info as three
/// self-contained zones arranged by [TheaterLayout] from a [TheaterLayoutConfig].
///
/// This screen only ASSEMBLES — it builds each zone with its data and hands the
/// set to the layout. It owns one piece of shared state, `_current` (the
/// episode in the video frame): the list selects into it (swap in place, no
/// navigation) and the video reports auto-advance back into it. It holds no
/// geometry; repositioning is entirely a [TheaterLayoutConfig] concern.
class TheaterScreen extends StatefulWidget {
  const TheaterScreen({
    super.key,
    required this.series,
    required this.initialEpisode,
    required this.services,
    required this.header,
    required this.onSettings,
    this.config = TheaterLayoutConfig.theaterDefault,
  });

  final Series series;
  final Episode initialEpisode;

  /// Every repository, the settings and the app-lifetime playback engine (see
  /// `LibraryServices`). The theater CONSUMES the engine; popping this route
  /// stops playback but leaves the engine alive.
  final LibraryServices services;

  /// The shared header actions (Scan / Unmatched), forwarded from the launching
  /// screen so the theater header is IDENTICAL to home/detail — same
  /// [HeaderActionsBar], only the back button differs.
  final HeaderHooks header;

  /// Returns a Future so this screen can await the window: Folders is a
  /// category inside it, and reordering them changes which copy plays.
  final Future<void> Function() onSettings;

  /// The arrangement. Defaults to the YouTube-style theater; a future Settings
  /// or drag-to-resize just supplies a different config — the zones are unchanged.
  final TheaterLayoutConfig config;

  @override
  State<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends State<TheaterScreen> with HeaderPublisher {
  late Episode _current;
  List<Episode>? _episodes; // null while first loading

  /// The show as last read — re-read with the episodes so the header and the
  /// info zone follow a rescan or a reassign instead of the push-time value.
  late Series _series = widget.series;

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

  /// Bumped when Settings closes over the player — see VideoZone.settingsRevision.
  int _settingsRevision = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialEpisode;
    _railFraction = widget.config.railFraction;
    // Follow the REAL window state. Seeded from it too, so entering the theater
    // while the window is already fullscreen renders correctly on frame one.
    _fullscreen = WindowChrome.fullscreen.value;
    WindowChrome.fullscreen.addListener(_onWindowFullscreenChanged);
    widget.services.scanning.addListener(_onScanningChanged);
    widget.services.scan.progress.addListener(_onScanningChanged);
    widget.services.unmatchedCount.addListener(_onScanningChanged);
    // The player is the ONLY place fullscreen has an exit (⛶ / Escape), so it
    // is the only place the window is allowed to enter it. Scoped to exactly
    // this screen's lifetime; the runner force-exits when it goes away.
    unawaited(WindowChrome.setFullscreenAllowed(true));
    unawaited(_loadRailFraction());
    unawaited(_loadEpisodes());
  }

  @override
  void dispose() {
    widget.services.scanning.removeListener(_onScanningChanged);
    widget.services.scan.progress.removeListener(_onScanningChanged);
    widget.services.unmatchedCount.removeListener(_onScanningChanged);
    _scanReload?.cancel();
    WindowChrome.fullscreen.removeListener(_onWindowFullscreenChanged);
    unawaited(WindowChrome.setFullscreenAllowed(false));
    super.dispose();
  }

  /// The window finished entering or leaving fullscreen — from ANY cause (our
  /// ⛶ / Escape, the green traffic light, Ctrl-Cmd-F, Mission Control). One
  /// path for all of them, which is what keeps OS-initiated changes in sync.
  void _onWindowFullscreenChanged() {
    if (!mounted) return;
    setState(() => _fullscreen = WindowChrome.fullscreen.value);
  }

  void _onScanningChanged() {
    if (!mounted) return;
    setState(() {});
    // Follow the scan like the show page does (see
    // `_SeriesDetailScreenState._scheduleScanReload`): the rail and the info
    // zone pick up episodes identified while the player is open.
    _scanReload?.cancel();
    if (widget.services.scanning.value) {
      _scanReload = Timer(kScanReloadDebounce, () {
        if (mounted) unawaited(_loadEpisodes());
      });
    } else {
      unawaited(_loadEpisodes());
    }
  }

  Timer? _scanReload;

  /// Already clamped by the repository (every setting is, on load).
  Future<void> _loadRailFraction() => guarded('rail fraction', () async {
    final stored = await widget.services.settings.loadRailFraction();
    if (mounted) setState(() => _railFraction = stored);
  });

  /// Overlapping loads (a scan report landing while a return-from-settings
  /// load is in flight): the older one finishing last must not win.
  int _loadGeneration = 0;

  Future<void> _loadEpisodes() => guarded('theater episodes', () async {
    final generation = ++_loadGeneration;
    final (eps, series) = await (
      widget.services.repository.episodesFor(widget.series.seriesId),
      widget.services.repository.seriesById(widget.series.seriesId),
    ).wait;
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _episodes = eps;
      // The show may have left the library mid-session; keep the last known
      // identity for the frame that is still playing rather than blanking it.
      if (series != null) _series = series;
    });
  });

  /// Enter/exit fullscreen. The ONE fullscreen path — the ⛶ button and the
  /// Escape shortcut both land here via [PlayerControlsActions.toggleFullscreen].
  ///
  /// Two separable things, which media_kit bundled into one route push and we
  /// keep apart:
  ///  1. LAYOUT — [_fullscreen] drives the layout config (video only, chrome
  ///     hidden). Pure setState; the widget tree keeps its shape so the video
  ///     zone is never rebuilt (see TheaterLayout's shape-invariance note).
  ///  2. THE WINDOW — [WindowChrome.setFullscreen], our own runner call. It is
  ///     BORDERLESS fullscreen (resize to the screen, hide the menu bar + Dock),
  ///     not a macOS fullscreen Space: the Space transition was a fixed ~400ms
  ///     system animation that made the window change and the layout change read
  ///     as two separate steps. Borderless has no transition, so both land
  ///     within a frame of each other.
  ///
  /// Tooltips are dismissed FIRST, synchronously, before the OS resizes the
  /// window: a tooltip mounted across an overlay-size change is the
  /// `size == theater.size` crash. TooltipDismissOnResize is the general net;
  /// this is the deterministic one for the path we control.
  void _toggleFullscreen() {
    // Ask the window, then wait to be told. No optimistic setState: the layout
    // must not move until the window has. That used to cost a visible step
    // because native fullscreen put a ~400ms Space transition in between;
    // borderless fullscreen has no transition, so the reply lands within a
    // frame and the two changes read as one motion. The reply arrives on
    // WindowChrome.fullscreen -> _onWindowFullscreenChanged.
    Tooltip.dismissAllToolTips();
    unawaited(WindowChrome.setFullscreen(!_fullscreen));
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
    unawaited(_loadEpisodes());
  }

  /// Settings opens over the player, and Sources is a category inside it:
  /// reordering there can change which copy of an episode plays, and this
  /// screen holds a resolved episode list, so it re-reads once the window
  /// closes. The caller already refreshes the screen BELOW us — this covers the
  /// one we are on. (The theater cannot see the window's outcome through the
  /// forwarded callback, so it always re-reads; that is one cached query, no
  /// scan and no network.)
  Future<void> _openSettings() async {
    await widget.onSettings();
    if (!mounted) return;
    // The PLAYING episode re-reads its settings too (skip mode, auto-play,
    // watched threshold) — they were read once per episode, so a change made
    // from inside the player used to apply only to the next one.
    setState(() => _settingsRevision++);
    unawaited(_loadEpisodes());
  }

  @override
  HeaderSpec buildHeaderSpec() => HeaderSpec(
    title: widget.services.scanning.value
        ? scanningTitle(widget.services.scan.progress.value)
        : _series.displayTitle,
    actions: AppActions(
      scanning: widget.services.scanning.value,
      unmatchedCount: widget.services.unmatchedCount.value,
      onScan: widget.header.onScan,
      // Leave the player FIRST: the Unmatched page must not open on top of a
      // playing frame (its audio would carry on behind it).
      onUnmatched: () {
        unawaited(Navigator.of(context).maybePop());
        widget.header.onUnmatched();
      },
      onSettings: _openSettings,
      progress: widget.services.scan.progress.value,
      onStopScan: widget.services.scanning.value
          ? widget.services.scan.stop
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    publishHeader();

    // Another page pushed OVER the player (Settings › Library › Unmatched
    // files, About › Licences) leaves this route mounted, so audio kept
    // playing behind an unrelated screen. `ModalRoute.of` subscribes to the
    // route's state, so this rebuilds when it stops being current.
    final obscured = !(ModalRoute.of(context)?.isCurrent ?? true);

    final zones = <TheaterZone, Widget>{
      TheaterZone.video: VideoZone(
        // Keyed by series so a different show gets a fresh playback frame;
        // within a series, the same frame swaps episodes in place.
        key: ValueKey(widget.series.seriesId),
        episode: _current,
        watchState: widget.services.watchState,
        watchOrder: widget.services.watchOrder,
        playback: widget.services.playback,
        settings: widget.services.settings,
        fullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
        settingsRevision: _settingsRevision,
        obscured: obscured,
        onEpisodeChanged: _onAdvanced,
      ),
      TheaterZone.seriesInfo: SeriesInfoZone(
        series: _series,
        // Null until the list has loaded — the zone then shows no count
        // rather than "0 episodes".
        episodeCount: _episodes?.length,
        nowPlaying: _current,
      ),
      TheaterZone.episodeList: EpisodeListZone(
        // Null = loading (a spinner), [] = genuinely nothing. The rail used
        // to say "No episodes here yet" during the query.
        episodes: _episodes,
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
      // The theater keeps its Material Scaffold and its own SHELL (NOT
      // the app shell's), but it no longer builds a HEADER. There is exactly ONE
      // header in the app now — the hoisted AppShell one — and this screen
      // feeds it like every other page, by publishing a HeaderSpec. Previously
      // this appBar was a SECOND header widget that traded places with the
      // hoisted one on entry and exit, which is what read as "two headers
      // swapping". The shell drops its FRAME for this route (see
      // FramelessPageRoute) so the player still looks immersive rather than
      // like a framed page, and hides the header outright in fullscreen.
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
            : () => widget.services.settings.setRailFraction(_railFraction),
      ),
    );
  }
}
