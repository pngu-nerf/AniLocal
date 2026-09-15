import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/watch_order_repository.dart';
import '../../../domain/repositories/watch_state_repository.dart';
import '../../../playback/playback_controller.dart';
import '../../theme/xp_tokens.dart';
import '../controls/player_control_bar.dart';
import '../controls/player_controls_state.dart';
import 'playback_session.dart';

/// The VIDEO zone: the embedded libmpv (media_kit) playback frame, driven by
/// our OWN control bar ([PlayerControls]). The same bar renders in windowed
/// mode and in fullscreen (a layout state on the theater, not a route), so
/// the two cannot drift and the skip affordances show in both.
///
/// This widget is the ADAPTER between the tree and a [PlaybackSession]: it
/// owns one session for its lifetime, relays the host's inputs (the episode
/// to play, the fullscreen flag, a settings change) into it, renders the
/// engine's texture with the bar over it, and commits progress when the app
/// itself is leaving. Every playback behaviour — resume, watched threshold,
/// skip detection, the up-next pre-roll, persistence, the media remote —
/// lives in the session, where it is tested without a widget or an engine.
///
/// Swap-in-place: when [episode] changes (list tap, or auto-advance) the
/// session re-opens in the same frame on the same controller — no navigation,
/// no duplicate player.
///
/// **Consumes the engine, does not own it.** [playback] is the app-lifetime
/// [PlaybackController] built at the composition root. The session opens
/// episodes on it and [PlaybackController.stop]s it on the way out; nothing
/// here may dispose it.
class VideoZone extends StatefulWidget {
  const VideoZone({
    super.key,
    required this.episode,
    required this.playback,
    required this.watchState,
    required this.watchOrder,
    required this.settings,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.settingsRevision = 0,
    this.obscured = false,
    this.onEpisodeChanged,
  });

  final Episode episode;

  /// The app-lifetime playback engine, injected — see the class doc.
  final PlaybackController playback;

  final WatchStateRepository watchState;
  final WatchOrderRepository watchOrder;

  /// App-wide settings (one injected object); the session reads auto-play,
  /// skip mode, and the watched threshold from it per episode.
  final SettingsRepository settings;

  /// Whether the theater is in fullscreen. Owned by the THEATER (it's a layout
  /// mode, not a playback fact); relayed into the shared control state so the
  /// bar can render the right ⛶ icon and pick its config.
  final bool fullscreen;

  /// The one fullscreen toggle, owned by the theater — relayed to the bar as
  /// [PlayerControlsActions.toggleFullscreen] for both ⛶ and Escape.
  final VoidCallback onToggleFullscreen;

  /// Bumped by the host each time the settings window closes over the player.
  /// A change makes the session re-read the settings the CURRENT episode plays
  /// under (skip mode, auto-play, watched threshold) — before this they were
  /// read once per episode, so a change made mid-episode applied only to the
  /// next one.
  final int settingsRevision;

  /// True while another page or dialog sits on top of the theater. Playback
  /// PAUSES on the transition to true (audio behind an unrelated screen is
  /// never what the viewer meant) and RESUMES on the transition back only if
  /// it was playing when it was covered.
  final bool obscured;

  final ValueChanged<Episode>? onEpisodeChanged;

  @override
  State<VideoZone> createState() => _VideoZoneState();
}

class _VideoZoneState extends State<VideoZone> {
  late final PlaybackSession _session;

  /// Commits progress when the APP itself is leaving (window loses focus /
  /// hidden / quit) — the graceful-exit save for departures that don't dispose
  /// this widget (a route pop does; a Cmd-Q / minimise doesn't). Best-effort on
  /// a hard quit; the session's periodic save remains the crash safety net.
  /// In-app route pushes don't change the app lifecycle, so this fires only on
  /// a real departure from the app, not on navigation within it.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _session = PlaybackSession(
      playback: widget.playback,
      watchState: widget.watchState,
      watchOrder: widget.watchOrder,
      settings: widget.settings,
      episode: widget.episode,
      fullscreen: widget.fullscreen,
      onToggleFullscreen: () => widget.onToggleFullscreen(),
      onEpisodeChanged: (e) => widget.onEpisodeChanged?.call(e),
    )..start();
    _lifecycle = AppLifecycleListener(onInactive: _session.persist);
  }

  @override
  void didUpdateWidget(VideoZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    _session.fullscreen = widget.fullscreen;
    if (widget.settingsRevision != oldWidget.settingsRevision) {
      unawaited(_session.reloadContext());
    }
    if (widget.obscured && !oldWidget.obscured) {
      _session.pauseForObscured();
    }
    if (!widget.obscured && oldWidget.obscured) {
      _session.resumeIfObscurePaused();
    }
    _session.select(widget.episode);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    // STOP, never dispose the engine: it is app-lifetime and injected. The
    // session commits the final position and stops playback exactly as the
    // zone used to; the Player survives for the next visit.
    unawaited(_session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A true-black VFD "stage" (Xp.well) so letterboxing reads as an unlit
    // display field, not a gap. The control bar is rendered by media_kit over
    // the texture via `controls:`, so it overlays the video here AND in
    // fullscreen automatically.
    return ColoredBox(
      color: Xp.well,
      child: Video(
        controller: widget.playback.controller,
        controls: (_) => PlayerControls(
          player: widget.playback.player,
          state: _session.controls,
          actions: _session.actions,
        ),
      ),
    );
  }
}
