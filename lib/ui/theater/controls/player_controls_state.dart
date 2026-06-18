import 'package:flutter/foundation.dart';

import '../../../domain/models/episode.dart';
import '../../../domain/models/skip_mode.dart';

/// The DOMAIN-side control state the bar needs that the media_kit player streams
/// don't carry: which episode is playing, whether a skip affordance is live,
/// and the up-next pre-roll. Engine state (position/duration/playing/volume/
/// tracks) comes straight from the player streams instead.
///
/// VideoZone owns a `ValueNotifier<PlayerControlsState>` and updates it; the
/// control bar listens. Because it's a shared [Listenable], the SAME instance
/// drives both the windowed and fullscreen renders of the one bar — neither can
/// go stale relative to the other.
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

  PlayerControlsState copyWith({
    Episode? episode,
    SkipMode? skipMode,
    bool? showSkipIntro,
    bool? showSkipOutro,
    Episode? upNext,
    bool clearUpNext = false,
    bool? preRollShowing,
    int? preRollSeconds,
  }) => PlayerControlsState(
    episode: episode ?? this.episode,
    skipMode: skipMode ?? this.skipMode,
    showSkipIntro: showSkipIntro ?? this.showSkipIntro,
    showSkipOutro: showSkipOutro ?? this.showSkipOutro,
    upNext: clearUpNext ? null : (upNext ?? this.upNext),
    preRollShowing: preRollShowing ?? this.preRollShowing,
    preRollSeconds: preRollSeconds ?? this.preRollSeconds,
  );
}

/// The DOMAIN-side actions the bar invokes — the ones that aren't plain player
/// calls. Engine actions (play/pause, seek, volume, subtitle track) the
/// controls call directly on the player. These four route back into VideoZone's
/// playback logic so behavior stays in one place.
@immutable
class PlayerControlsActions {
  const PlayerControlsActions({
    required this.skipIntro,
    required this.skipOutro,
    required this.playNext,
    required this.cancelPreRoll,
  });

  final VoidCallback skipIntro;
  final VoidCallback skipOutro;
  final VoidCallback playNext;
  final VoidCallback cancelPreRoll;
}
