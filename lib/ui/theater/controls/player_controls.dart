import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show isFullscreen, toggleFullscreen;

import 'player_controls_state.dart';

/// The individual, position-agnostic player controls. Each takes only what it
/// needs (the player for engine state/actions; the shared state notifier for
/// domain bits; the actions bundle for domain actions) and is placed by the
/// config — none knows which slot it's in. Engine-reactive controls read player
/// streams directly (so they update identically in windowed and fullscreen).

const _iconColor = Colors.white;

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
        return IconButton(
          color: _iconColor,
          tooltip: playing ? 'Pause' : 'Play',
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: player.playOrPause,
        );
      },
    );
  }
}

/// `m:ss / m:ss` (or `h:mm:ss`) current / total.
class TimeLabel extends StatelessWidget {
  const TimeLabel({super.key, required this.player});
  final Player player;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, posSnap) => StreamBuilder<Duration>(
        stream: player.stream.duration,
        initialData: player.state.duration,
        builder: (context, durSnap) {
          final pos = posSnap.data ?? Duration.zero;
          final dur = durSnap.data ?? Duration.zero;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_fmt(pos)} / ${_fmt(dur)}',
              style: const TextStyle(
                color: _iconColor,
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 12,
              ),
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
            IconButton(
              color: _iconColor,
              tooltip: muted ? 'Unmute' : 'Mute',
              icon: Icon(
                muted
                    ? Icons.volume_off
                    : volume < 50
                    ? Icons.volume_down
                    : Icons.volume_up,
              ),
              onPressed: () => player.setVolume(muted ? 100 : 0),
            ),
            if (!compact)
              SizedBox(
                width: 84,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: volume,
                    max: 100,
                    onChanged: player.setVolume,
                  ),
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
        return PopupMenuButton<SubtitleTrack>(
          tooltip: 'Subtitles',
          icon: const Icon(Icons.closed_caption_outlined, color: _iconColor),
          onSelected: player.setSubtitleTrack,
          itemBuilder: (context) => [
            for (final t in tracks)
              CheckedPopupMenuItem<SubtitleTrack>(
                value: t,
                checked: t == current,
                child: Text(_label(t)),
              ),
          ],
        );
      },
    );
  }
}

/// The "settings" hub — a small menu, not a single-purpose button. Playback
/// speed is one NESTED subsection (a submenu); more sections slot in beside it
/// later without changing the bar. The slot/config system treats it like any
/// other control.
class SettingsControl extends StatelessWidget {
  const SettingsControl({super.key, required this.player});
  final Player player;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        color: _iconColor,
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
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
      ],
    );
  }
}

class FullscreenButton extends StatelessWidget {
  const FullscreenButton({super.key});

  @override
  Widget build(BuildContext context) {
    final full = isFullscreen(context);
    return IconButton(
      color: _iconColor,
      tooltip: full ? 'Exit fullscreen' : 'Fullscreen',
      icon: Icon(full ? Icons.fullscreen_exit : Icons.fullscreen),
      onPressed: () => toggleFullscreen(context),
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(intro ? Icons.fast_forward : Icons.skip_next),
            label: Text(intro ? 'Skip Intro' : 'Skip Outro'),
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
        final title = next.title ?? 'Episode ${next.number}';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Up next: $title · ${s.preRollSeconds}s',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _iconColor, fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              FilledButton(onPressed: onPlayNow, child: const Text('Play now')),
            ],
          ),
        );
      },
    );
  }
}
