import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../data/paths.dart' show basenameOf;
import '../../../domain/format_duration.dart';
import '../../../domain/models/episode.dart';
import '../../theme/vfd_readout.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import 'player_controls_state.dart';
import 'segmented_meter.dart';
import 'vfd_control.dart';

// NOTE: `playerIsFullscreen` + `hasInheritedAncestorWithoutSubscribing` used to
// live here — a non-subscribing read of media_kit's route-scoped
// `FullscreenInheritedWidget`, written to dodge `_dependents.isEmpty` on
// fullscreen exit. Both are GONE: fullscreen is no longer a route, so there is
// no route-scoped inherited widget to read, subscribe to, or outlive. The mode
// now arrives as ordinary state on `PlayerControlsState.fullscreen`.

/// The individual, position-agnostic player controls. Each takes only what it
/// needs (the player for engine state/actions; the shared state notifier for
/// domain bits; the actions bundle for domain actions) and is placed by the
/// config — none knows which slot it's in. Engine-reactive controls read player
/// streams directly (so they update identically in windowed and fullscreen).

// Every control below is a DISPLAY element on the bar's VFD panel, so none of
// them styles itself: icons go through [VfdIconButton], legends through
// [VfdActionButton], readouts through [VfdReadout] at [kVfdBarPitch]. The look
// lives in `vfd_control.dart`; this file stays about what each control DOES.

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        // Both transport legends are etched, and the CURRENT state is the lit
        // one — a deck's play/pause pair, not a button whose glyph swaps. The
        // tooltip still names the ACTION, and the tap is unchanged.
        return VfdIconButton(
          lit: true,
          tooltip: playing ? 'Pause' : 'Play',
          icon: playing ? Icons.play_arrow : Icons.pause,
          ghost: playing ? Icons.pause : Icons.play_arrow,
          onPressed: player.playOrPause,
        );
      },
    );
  }
}

/// `m:ss / m:ss` (or `h:mm:ss`) current / total.
///
/// Stateful for one reason: the position stream ticks several times a second
/// and the readout shows whole seconds, so it listens to the SECOND — the
/// stream mapped and de-duplicated once, here, not rebuilt per frame. Every
/// position event used to redraw ~250 blurred dots.
class TimeLabel extends StatefulWidget {
  const TimeLabel({super.key, required this.player});
  final Player player;

  @override
  State<TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends State<TimeLabel> {
  late Stream<int> _seconds = _secondsOf(widget.player);

  static Stream<int> _secondsOf(Player p) =>
      p.stream.position.map((d) => d.inSeconds).distinct();

  @override
  void didUpdateWidget(TimeLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player != oldWidget.player) _seconds = _secondsOf(widget.player);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _seconds,
      initialData: widget.player.state.position.inSeconds,
      builder: (context, posSnap) => StreamBuilder<Duration>(
        stream: widget.player.stream.duration,
        initialData: widget.player.state.duration,
        builder: (context, durSnap) {
          final pos = Duration(seconds: posSnap.data ?? 0);
          final dur = durSnap.data ?? Duration.zero;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            // A dot-matrix time readout — the shared display role, at the
            // bar's one readout pitch so it and the EP readout are the same
            // size by construction.
            child: VfdReadout(
              '${formatDuration(pos)} / ${formatDuration(dur)}',
              dotPitch: kVfdBarPitch,
            ),
          );
        },
      ),
    );
  }
}

class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key, required this.player, this.compact = false});
  final Player player;

  /// When the bar is narrow, drop the inline slider and keep just the
  /// mute/level icon — so the row adapts instead of overflowing.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snap) {
        final volume = (snap.data ?? 100).clamp(0.0, 100.0);
        final muted = volume == 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VfdIconButton(
              tooltip: muted ? 'Unmute' : 'Mute',
              icon: muted
                  ? Icons.volume_off
                  : volume < 50
                  ? Icons.volume_down
                  : Icons.volume_up,
              onPressed: () => player.setVolume(muted ? 100 : 0),
            ),
            if (!compact)
              SizedBox(
                width: 84,
                // The level is the SEEK BAR's meter, cell for cell (shared
                // painter) — it was the last stock Material widget on the
                // panel, and a smooth continuous slider among quantized lit
                // cells is what read as app UI dropped onto a display. Same
                // footprint, same live-set-on-drag contract the Slider had, so
                // volume behaves exactly as before; mute now shows as a meter
                // with nothing lit, which is what a deck does.
                child: VfdLevelMeter(
                  fraction: volume / 100,
                  semanticLabel: 'Volume',
                  color: Xp.accent,
                  peakColor: Xp.accentBright,
                  onChanged: (f) => player.setVolume(f * 100),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SubtitlesControl extends StatelessWidget {
  const SubtitlesControl({super.key, required this.player});
  final Player player;

  static String _label(SubtitleTrack t) {
    if (t.id == 'no') return 'Off';
    if (t.id == 'auto') return 'Auto';
    final bits = [
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    return bits.isEmpty ? 'Track ${t.id}' : bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, _) {
        final tracks = player.state.tracks.subtitle;
        final current = player.state.track.subtitle;
        // CC is a legend with a real on/off state: lit while a track is
        // showing, dark when subtitles are off. Display state only — the tap
        // still opens the same track menu.
        final on = current.id != 'no';
        // PopupMenuButton builds its own IconButton, so its Material ink can't
        // be styled through our own button. Zeroing the overlay colours for
        // this subtree is the narrow way to keep the panel free of the grey
        // ripple, which on true black reads as a smudge rather than feedback.
        return Theme(
          data: Theme.of(context).copyWith(
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
          ),
          child: PopupMenuButton<SubtitleTrack>(
            tooltip: 'Subtitles',
            icon: VfdGlyph(
              Icons.closed_caption_outlined,
              color: on ? Xp.accentBright : Xp.accent.withValues(alpha: 0.35),
            ),
            onSelected: player.setSubtitleTrack,
            itemBuilder: (context) => [
              for (final t in tracks)
                CheckedPopupMenuItem<SubtitleTrack>(
                  value: t,
                  checked: t == current,
                  child: Text(_label(t)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The "settings" hub — a small menu, not a single-purpose button. Playback
/// speed is one NESTED subsection (a submenu); **Copy** is another, shown
/// only for an episode that exists in more than one folder and only when the
/// host can pin sources — the walkthrough found that switching copies meant
/// leaving the player for the show page and back. More sections slot in
/// beside these without changing the bar.
class SettingsControl extends StatelessWidget {
  const SettingsControl({
    super.key,
    required this.player,
    this.state,
    this.actions,
  });
  final Player player;
  final ValueListenable<PlayerControlsState>? state;
  final PlayerControlsActions? actions;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    if (state == null) return _menu(context, null);
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) => _menu(context, s.episode),
    );
  }

  Widget _menu(BuildContext context, Episode? episode) {
    final selectSource = actions?.selectSource;
    return MenuAnchor(
      builder: (context, controller, child) => VfdIconButton(
        tooltip: 'Settings',
        icon: Icons.settings_outlined,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Icons.speed),
          menuChildren: [
            for (final r in _rates)
              MenuItemButton(
                leadingIcon: player.state.rate == r
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                onPressed: () => player.setRate(r),
                child: Text('${r}x'),
              ),
          ],
          child: const Text('Playback speed'),
        ),
        if (episode != null &&
            episode.hasMultipleSources &&
            selectSource != null)
          SubmenuButton(
            leadingIcon: const Icon(Icons.folder_copy_outlined),
            menuChildren: [
              MenuItemButton(
                leadingIcon: episode.pinnedSourceFolder == null
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                onPressed: () => selectSource(null),
                child: const Text('Automatic (highest priority)'),
              ),
              for (final s in episode.sources)
                MenuItemButton(
                  // The pinned copy is checked; unpinned, the copy that is
                  // playing (the default) is.
                  leadingIcon:
                      episode.isPinned(s) ||
                          (episode.pinnedSourceFolder == null &&
                              s.fileRef == episode.fileRef)
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  onPressed: () => selectSource(s),
                  child: Text(
                    '${basenameOf(s.folderPath)} › ${basenameOf(s.fileRef)}',
                  ),
                ),
            ],
            child: const Text('Sources'),
          ),
      ],
    );
  }
}

/// The ⛶ toggle. Reads the mode from the shared state notifier and calls the
/// one fullscreen action — no [BuildContext] probing, no route.
class FullscreenButton extends StatelessWidget {
  const FullscreenButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  final ValueListenable<PlayerControlsState> state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) => VfdIconButton(
        tooltip: s.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
        icon: s.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        // Tooltips are dismissed before the window resizes — see the toggle in
        // TheaterScreen and TooltipDismissOnResize.
        onPressed: onPressed,
      ),
    );
  }
}

/// Transient: a "Skip Intro" / "Skip Outro" button that renders only while its
/// window is active (button mode). Same widget in both modes — which is why the
/// skip button now appears in fullscreen.
class SkipButton extends StatelessWidget {
  const SkipButton({
    super.key,
    required this.state,
    required this.intro,
    required this.onPressed,
  });

  final ValueListenable<PlayerControlsState> state;
  final bool intro;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) {
        final show = intro ? s.showSkipIntro : s.showSkipOutro;
        if (!show) return const SizedBox.shrink();
        // A lit display segment — armed by definition, since it only shows
        // inside its skip window. It reads as part of the panel it sits on
        // rather than a chassis key laid over the screen.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: VfdActionButton(
            lit: true,
            icon: intro ? Icons.fast_forward : Icons.skip_next,
            label: intro ? 'SKIP INTRO' : 'SKIP OUTRO',
            onPressed: onPressed,
          ),
        );
      },
    );
  }
}

/// Transient: the up-next pre-roll, as a compact inline control (was a floating
/// card). Counts down, advances at zero (driven by VideoZone), cancelable, with
/// an immediate "Play now". Renders nothing until the pre-roll is live.
class UpNextControl extends StatelessWidget {
  const UpNextControl({
    super.key,
    required this.state,
    required this.onPlayNow,
    required this.onCancel,
  });

  final ValueListenable<PlayerControlsState> state;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) {
        final next = s.upNext;
        if (!s.preRollShowing || next == null) return const SizedBox.shrink();
        final title = next.displayTitle;
        // A compact pair of display controls — the armed "play next" segment
        // (lit, carrying the countdown) + a glyph-only cancel — so the up-next
        // reads as the same family as Skip Intro/Outro. The next-episode title
        // stays in the tooltip: it is running text, which the dot-matrix legend
        // deliberately cannot render, and it would overflow a narrow bar.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VfdActionButton(
                lit: true,
                icon: Icons.play_arrow,
                // Legend charset is the dot-matrix font's (no interpunct), so
                // the countdown reads as plain segments.
                label: 'PLAY NEXT ${s.preRollSeconds}S',
                tooltip: 'Play next: $title',
                onPressed: onPlayNow,
              ),
              const SizedBox(width: 6),
              VfdIconButton(
                icon: Icons.close,
                tooltip: 'Cancel',
                onPressed: onCancel,
                size: 16,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What a failed open looks like: a headline in the panel's error colour and
/// the engine's own line under it, over the frame that stayed black. Renders
/// nothing while playback is healthy. The engine's text is shown because a
/// viewer needs to know WHICH file libmpv refused — that line names it — and
/// the same text is in the diagnostics ring for a report.
class PlaybackErrorNotice extends StatelessWidget {
  const PlaybackErrorNotice({super.key, required this.state, this.onRetry});

  final ValueListenable<PlayerControlsState> state;

  /// Re-open the episode where it was. A replugged drive used to need a
  /// click off the episode and back; the error itself now carries the way
  /// out. Null hides the button.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) {
        final message = s.errorMessage;
        final notice = s.notice;
        if (message == null && notice == null) return const SizedBox.shrink();
        if (message == null) {
          // A transient line — "Playing the copy in X instead" — not a failure.
          return Padding(
            padding: const EdgeInsets.all(Xp.spaceXl),
            child: Text(
              notice!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Xp.textDim,
                fontSize: Xp.fontSizeBody,
              ),
            ),
          );
        }
        // The instrument's sunken display well — the same panel the show
        // page's error state sits in. OPAQUE on purpose: a failed OPEN leaves
        // the frame black and a stream that died mid-play leaves its last
        // picture, and a translucent backing looked like nothing over the one
        // and like a glass card over the other — two error screens for one
        // widget. The well looks the same over both.
        return Padding(
          padding: const EdgeInsets.all(Xp.spaceXl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: XpPanel(
              inset: true,
              padding: const EdgeInsets.all(Xp.spaceL),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Couldn’t play this episode',
                    style: TextStyle(
                      color: Xp.error,
                      fontSize: Xp.fontSizeTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Xp.spaceS),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Xp.textDim,
                      fontSize: Xp.fontSizeCaption,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: Xp.spaceM),
                    XpButton(
                      lit: true,
                      icon: Icons.refresh,
                      label: 'Retry',
                      onPressed: onRetry,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The centered EP readout — "EP 12" in dot matrix, the panel's one piece of
/// pure information.
///
/// It reads the episode straight off the shared state notifier, like every
/// other domain-aware control here, so it is correct in both modes and updates
/// on swap-in-place without the bar knowing anything about episodes.
///
/// Graceful by construction: a standard position renders "EP n"; a non-standard
/// one (a special or extra, which the library models as position ≤ 0) has no
/// meaningful number, so it renders the label alone rather than "EP 0" or a
/// negative. No episode at all renders nothing. It is DROPPED in [compact] —
/// the same width rule the time label follows — because a dot-matrix readout
/// cannot ellipsize, so at narrow widths it yields the room instead of
/// squeezing the transport.
class EpisodeReadout extends StatelessWidget {
  const EpisodeReadout({super.key, required this.state, this.compact = false});

  final ValueListenable<PlayerControlsState> state;
  final bool compact;

  /// The legend for an episode position. Kept as a pure static so the rule is
  /// testable without pumping the bar.
  static String? labelFor(Episode? episode) {
    if (episode == null) return null;
    final n = episode.number;
    return n >= 1 ? 'EP $n' : 'SPECIAL';
  }

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox.shrink();
    return ValueListenableBuilder<PlayerControlsState>(
      valueListenable: state,
      builder: (context, s, _) {
        final label = labelFor(s.episode);
        if (label == null) return const SizedBox.shrink();
        return VfdReadout(label, dotPitch: kVfdBarPitch);
      },
    );
  }
}
