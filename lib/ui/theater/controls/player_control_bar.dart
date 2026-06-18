import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' show isFullscreen;

import 'control_bar_config.dart';
import 'player_controls.dart';
import 'player_controls_state.dart';
import 'seek_bar.dart';

/// THE control bar — one implementation, rendered in BOTH windowed and
/// fullscreen. It arranges controls into slots from a [ControlBarConfig],
/// choosing the windowed vs fullscreen config purely by [isFullscreen] — never
/// a different control set. (media_kit's fullscreen route reuses the same
/// `controls` builder + controller, so this same widget is what renders there.)
class PlayerControlBar extends StatelessWidget {
  const PlayerControlBar({
    super.key,
    required this.player,
    required this.state,
    required this.actions,
    this.windowed = ControlBarConfig.windowedDefault,
    this.fullscreen = ControlBarConfig.fullscreenDefault,
  });

  final Player player;
  final ValueListenable<PlayerControlsState> state;
  final PlayerControlsActions actions;
  final ControlBarConfig windowed;
  final ControlBarConfig fullscreen;

  Widget _control(PlayerControl c, {bool compact = false}) => switch (c) {
    PlayerControl.playPause => PlayPauseButton(player: player),
    // The seek bar reads the current episode's cached skip windows so it can
    // shade the OP/ED regions on the real timeline.
    PlayerControl.seekBar => ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) => SeekBar(
        player: player,
        introSkip: s.episode?.introSkip,
        outroSkip: s.episode?.outroSkip,
      ),
    ),
    PlayerControl.timeLabel => TimeLabel(player: player),
    PlayerControl.volume => VolumeControl(player: player, compact: compact),
    PlayerControl.subtitles => SubtitlesControl(player: player),
    PlayerControl.settings => SettingsControl(player: player),
    PlayerControl.fullscreen => const FullscreenButton(),
    PlayerControl.skipIntro => SkipButton(
      state: state,
      intro: true,
      onPressed: actions.skipIntro,
    ),
    PlayerControl.skipOutro => SkipButton(
      state: state,
      intro: false,
      onPressed: actions.skipOutro,
    ),
    PlayerControl.upNext => UpNextControl(
      state: state,
      onPlayNow: actions.playNext,
      onCancel: actions.cancelPreRoll,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final config = isFullscreen(context) ? fullscreen : windowed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A right-aligned row OVER the timeline (Skip Intro/Outro live here).
        if (config.controlsIn(ControlSlot.aboveBar).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final c in config.controlsIn(ControlSlot.aboveBar))
                  _control(c),
              ],
            ),
          ),
        for (final c in config.controlsIn(ControlSlot.scrubber))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: _control(c),
          ),
        // Button row — adaptive so it lays out cleanly at any width, not just
        // fullscreen-wide: the time label flexes (ellipsizes), the center flexes,
        // and below a breakpoint the inline volume slider folds to its icon.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              return Row(
                children: [
                  // The time label is a PLAIN child (no Flexible): a flex child
                  // here would split the row's free space with the Expanded
                  // center and leave the right controls short of the edge. To
                  // stay clean when narrow it's simply dropped in compact mode,
                  // so the Expanded center is the only flex child and the right
                  // slot always reaches the right edge.
                  for (final c in config.controlsIn(ControlSlot.left))
                    if (c != PlayerControl.timeLabel || !compact)
                      _control(c, compact: compact),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in config.controlsIn(ControlSlot.center))
                          Flexible(child: _control(c, compact: compact)),
                      ],
                    ),
                  ),
                  for (final c in config.controlsIn(ControlSlot.right))
                    _control(c, compact: compact),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Root of the controls overlay — what media_kit's `Video(controls:)` renders
/// over the texture, in both windowed and fullscreen. Owns auto-hide (show on
/// hover/move, fade out after idle while playing) and a bottom scrim for
/// legibility; the bar itself is [PlayerControlBar].
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.state,
    required this.actions,
  });

  final Player player;
  final ValueListenable<PlayerControlsState> state;
  final PlayerControlsActions actions;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _visible = true;
  Timer? _idle;

  /// The player's own keyboard-focus node. We OWN it (not a one-shot autofocus)
  /// and reclaim it on any interaction, so shortcuts survive every focus-stealing
  /// path: clicking a control, hovering back over the video, returning from
  /// fullscreen. (Clicking the sibling episode rail can't steal it either — the
  /// rail's items are canRequestFocus:false.)
  final FocusNode _focus = FocusNode(debugLabel: 'AniLocal player');

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 3), () {
      // Only auto-hide while actually playing; a paused player keeps controls.
      if (mounted && widget.player.state.playing) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Keyboard shortcuts, live in BOTH modes because this overlay renders in
  /// both. They DELEGATE to the same paths the on-screen controls use — never a
  /// parallel implementation: space → playOrPause; ←/→ → seek ±10s via the
  /// shared [Player.seek] (the seek bar's primitive); ↑/↓ → volume. Seeking
  /// PAST the end routes to [PlayerControlsActions.playNext] — i.e.
  /// `PlaybackController.advanceToNext()`, the same advance the up-next pre-roll
  /// and auto-advance use ("seek past end starts the next episode").
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final p = widget.player;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      p.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      p.setVolume((p.state.volume + 5).clamp(0.0, 100.0));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      p.setVolume((p.state.volume - 5).clamp(0.0, 100.0));
    } else {
      return KeyEventResult.ignored;
    }
    _show(); // surface the bar on any keyboard interaction
    return KeyEventResult.handled;
  }

  void _seekRelative(Duration delta) {
    final p = widget.player;
    final dur = p.state.duration;
    final target = p.state.position + delta;
    // Forward past the end → advance to the next episode (same action as the
    // up-next countdown), not a clamp/no-op.
    if (delta > Duration.zero && dur > Duration.zero && target >= dur) {
      widget.actions.playNext();
      return;
    }
    final clamped = target < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && target > dur ? dur : target);
    p.seek(clamped); // the same seek the seek bar + skip buttons use
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      // Any pointer-down inside the player reclaims keyboard focus (clicking the
      // video, the scrim, or a control) — so shortcuts keep working after any
      // in-player interaction.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _focus.requestFocus(),
        child: MouseRegion(
          onEnter: (_) {
            _show();
            _focus
                .requestFocus(); // reclaim e.g. after returning from fullscreen
          },
          onHover: (_) => _show(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_visible,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        // The bar's controls must NEVER hold keyboard focus, so a
                        // focused slider/button can't swallow space/←/→ — the
                        // player's shortcuts always win. They stay fully
                        // mouse-operable (focus ≠ pointer input).
                        child: Focus(
                          canRequestFocus: false,
                          descendantsAreFocusable: false,
                          child: PlayerControlBar(
                            player: widget.player,
                            state: widget.state,
                            actions: widget.actions,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
