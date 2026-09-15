import 'package:flutter/foundation.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/models/episode_source.dart';
import '../../../domain/models/skip_mode.dart';
import '../../../domain/models/skip_range.dart';

/// The DOMAIN-side control state the bar needs that the media_kit player streams
/// don't carry: which episode is playing, whether a skip affordance is live,
/// and the up-next pre-roll. Engine state (position/duration/playing/volume/
/// tracks) comes straight from the player streams instead.
///
/// VideoZone owns a `ValueNotifier<PlayerControlsState>` and updates it; the
/// control bar listens. ONE instance drives the bar in every mode, so nothing
/// can go stale relative to anything else.
///
/// [fullscreen] rides here too. It used to be read from media_kit's
/// route-scoped `FullscreenInheritedWidget` — the cross-route inherited
/// dependency that caused the `_dependents.isEmpty` crash. Fullscreen is now
/// plain state owned by the theater and published through this same notifier,
/// so the bar learns about it the same way it learns everything else, and there
/// is no route-scoped widget for a control to outlive.
@immutable
class PlayerControlsState {
  const PlayerControlsState({
    this.episode,
    this.skipMode = SkipMode.button,
    this.showSkipIntro = false,
    this.showSkipOutro = false,
    this.upNext,
    this.preRollShowing = false,
    this.preRollSeconds = 0,
    this.fullscreen = false,
    this.errorMessage,
    this.notice,
  });

  final Episode? episode;
  final SkipMode skipMode;

  /// Button-mode affordance visibility (auto mode seeks without a button).
  final bool showSkipIntro;
  final bool showSkipOutro;

  /// The resolved next episode, or null at a season boundary.
  final Episode? upNext;
  final bool preRollShowing;
  final int preRollSeconds;

  /// Whether the player is filling the window (chrome hidden + OS fullscreen).
  /// STATE, not a route — see the class doc.
  final bool fullscreen;

  /// The engine's last failure for THIS episode (a missing file, an unreadable
  /// container, a codec libmpv lacks), or null while playback is healthy.
  /// Cleared by the next open. Rendered over the frame so a failure is never a
  /// silent black screen.
  final String? errorMessage;

  /// A transient, non-error line over the frame — "Playing the copy in X
  /// instead" after a fall-through. Cleared by the session a few seconds on.
  final String? notice;

  /// The skip windows the timeline shades. Nothing in [SkipMode.off]: a viewer
  /// who turned skipping off asked not to be shown where the themes are.
  SkipRange? get introMarker =>
      skipMode == SkipMode.off ? null : episode?.introSkip;
  SkipRange? get outroMarker =>
      skipMode == SkipMode.off ? null : episode?.outroSkip;

  PlayerControlsState copyWith({
    Episode? episode,
    SkipMode? skipMode,
    bool? showSkipIntro,
    bool? showSkipOutro,
    Episode? upNext,
    bool clearUpNext = false,
    bool? preRollShowing,
    int? preRollSeconds,
    bool? fullscreen,
    String? errorMessage,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) => PlayerControlsState(
    episode: episode ?? this.episode,
    skipMode: skipMode ?? this.skipMode,
    showSkipIntro: showSkipIntro ?? this.showSkipIntro,
    showSkipOutro: showSkipOutro ?? this.showSkipOutro,
    upNext: clearUpNext ? null : (upNext ?? this.upNext),
    preRollShowing: preRollShowing ?? this.preRollShowing,
    preRollSeconds: preRollSeconds ?? this.preRollSeconds,
    fullscreen: fullscreen ?? this.fullscreen,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

/// The DOMAIN-side actions the bar invokes — the ones that aren't plain player
/// calls. Engine actions (play/pause, seek, volume, subtitle track) the
/// controls call directly on the player. These route back into VideoZone's
/// playback logic (and, for fullscreen, the theater's) so behavior stays in one
/// place.
@immutable
class PlayerControlsActions {
  const PlayerControlsActions({
    required this.skipIntro,
    required this.skipOutro,
    required this.playNext,
    required this.cancelPreRoll,
    required this.toggleFullscreen,
    this.selectSource,
    this.retry,
  });

  final VoidCallback skipIntro;
  final VoidCallback skipOutro;
  final VoidCallback playNext;
  final VoidCallback cancelPreRoll;

  /// Enter/exit fullscreen. Replaces media_kit's `toggleFullscreen(context)`,
  /// which pushed a route; this flips the theater's own state and drives the OS
  /// window directly. Both the ⛶ button and the Escape shortcut call it, so
  /// there is still exactly ONE fullscreen path.
  final VoidCallback toggleFullscreen;

  /// Play this episode from another of its copies (null = back to the
  /// folder-priority default), keeping the position. Absent when the host
  /// cannot pin sources; the bar then shows no Copy section.
  final void Function(EpisodeSource? source)? selectSource;

  /// Re-open the current episode where it was, after a failure. Absent when
  /// the host has no session (previews).
  final VoidCallback? retry;
}
