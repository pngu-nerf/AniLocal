import 'package:flutter/foundation.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/models/skip_mode.dart';

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
  }) => PlayerControlsState(
    episode: episode ?? this.episode,
    skipMode: skipMode ?? this.skipMode,
    showSkipIntro: showSkipIntro ?? this.showSkipIntro,
    showSkipOutro: showSkipOutro ?? this.showSkipOutro,
    upNext: clearUpNext ? null : (upNext ?? this.upNext),
    preRollShowing: preRollShowing ?? this.preRollShowing,
    preRollSeconds: preRollSeconds ?? this.preRollSeconds,
    fullscreen: fullscreen ?? this.fullscreen,
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
}
