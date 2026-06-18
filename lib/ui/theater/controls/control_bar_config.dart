import 'package:flutter/foundation.dart';

/// Every control the player bar can render. Each is a self-contained widget
/// (see `player_controls.dart`) that knows nothing about where it sits — the
/// config below places it.
///
/// Some are TRANSIENT ([skipIntro], [skipOutro], [upNext]): they're slotted like
/// any other control but render nothing until they're relevant. Putting them in
/// the slot system (rather than hard-positioned overlays) is exactly what makes
/// them appear in fullscreen too — same bar, same config-driven placement.
enum PlayerControl {
  playPause,
  seekBar,
  timeLabel,
  skipIntro,
  skipOutro,
  upNext,
  volume,
  subtitles,
  settings,
  fullscreen,
}

/// Named regions of the bar, top to bottom. [aboveBar] is a row OVER the seek
/// bar (right-aligned — where transient affordances like Skip Intro sit, clear
/// of the timeline); [scrubber] is the full-width seek-bar row; [left]/[center]
/// /[right] are the button row beneath it. Adding a region (as [aboveBar] was)
/// is a layout-layer change here + one row in the layout — never a control
/// change.
enum ControlSlot { aboveBar, scrubber, left, center, right }

/// The single source of truth for the control bar's arrangement — parallel to
/// `TheaterLayoutConfig` for the zones. It maps each slot to an ORDERED list of
/// controls (list order = left-to-right within the slot). A control's presence
/// in a slot is its visibility; absence hides it.
///
/// The consequences the brief asks for are by construction:
///  - **Move a control**: put it in a different slot's list.
///  - **Reorder**: change its index within a slot's list.
///  - **Hide**: remove it from every slot.
/// None of those touch a control widget. A future settings UI just writes a
/// different [ControlBarConfig]; nothing else changes.
///
/// THE one-bar-both-modes seam: [windowedDefault] and [fullscreenDefault] are
/// two configs for the SAME bar. The player renders one control-bar widget in
/// both windowed (inside VideoZone) and fullscreen, choosing the config by mode
/// — never a different control set. So fullscreen can't silently drop a control
/// (the historical skip-button-missing bug): both modes carry the full set
/// unless a config deliberately omits one.
@immutable
class ControlBarConfig {
  const ControlBarConfig({required this.slots});

  /// Ordered controls per slot. Left-to-right within each slot.
  final Map<ControlSlot, List<PlayerControl>> slots;

  List<PlayerControl> controlsIn(ControlSlot slot) =>
      slots[slot] ?? const <PlayerControl>[];

  bool shows(PlayerControl control) =>
      slots.values.any((list) => list.contains(control));

  ControlBarConfig copyWith({Map<ControlSlot, List<PlayerControl>>? slots}) =>
      ControlBarConfig(slots: slots ?? this.slots);

  /// Windowed (in-VideoZone) arrangement. Skip intro/outro sit ABOVE the
  /// timeline (right-aligned, clear of the scrubber); the up-next pre-roll sits
  /// centered in the button row. Right slot is left-to-right `volume, subtitles,
  /// settings, fullscreen` (so right-to-left it reads settings/subtitles/volume,
  /// per the brief, with fullscreen pinned rightmost). Moving Skip Intro here
  /// from the center was a slot reassignment (config) — but "above the timeline"
  /// needed the [ControlSlot.aboveBar] region added first (see the flag note).
  static const ControlBarConfig windowedDefault = ControlBarConfig(
    slots: {
      ControlSlot.aboveBar: [PlayerControl.skipIntro, PlayerControl.skipOutro],
      ControlSlot.scrubber: [PlayerControl.seekBar],
      ControlSlot.left: [PlayerControl.playPause, PlayerControl.timeLabel],
      ControlSlot.center: [PlayerControl.upNext],
      ControlSlot.right: [
        PlayerControl.volume,
        PlayerControl.subtitles,
        PlayerControl.settings,
        PlayerControl.fullscreen,
      ],
    },
  );

  /// Fullscreen arrangement. Deliberately the SAME control set as windowed —
  /// this is the whole point: fullscreen is a config of the one bar, so every
  /// control (including skip intro/outro) is present in both modes. Diverge it
  /// later (e.g. denser spacing, extra controls) by editing only this map.
  static const ControlBarConfig fullscreenDefault = windowedDefault;
}
