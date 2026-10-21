import 'package:flutter/services.dart';

import 'player_shortcuts.dart';

/// What a player shortcut does, in words — ONE place, like `skipModeLabel`,
/// so the reference in Settings › About and any future tooltip agree. The
/// step sizes are interpolated from the constants the handler uses, so a
/// retuned seek step cannot leave the reference lying.
String playerShortcutLabel(PlayerShortcut shortcut) => switch (shortcut) {
  PlayerShortcut.playPause => 'Play / pause',
  PlayerShortcut.seekForward => 'Forward ${kSeekStep.inSeconds} s',
  PlayerShortcut.seekBack => 'Back ${kSeekStep.inSeconds} s',
  PlayerShortcut.volumeUp => 'Volume up ${kVolumeStep.round()} %',
  PlayerShortcut.volumeDown => 'Volume down ${kVolumeStep.round()} %',
};

/// The glyph a reference shows for a key. `keyLabel` says "Arrow Right" and
/// renders Space as a blank, so the handful the app uses are named here; any
/// other key falls back to its label.
String keyGlyph(LogicalKeyboardKey key) => _glyphs[key] ?? key.keyLabel;

// A `final` map, not `const`: LogicalKeyboardKey overrides `==`, which a
// constant map's keys may not (the same reason `playerShortcuts` is final).
final Map<LogicalKeyboardKey, String> _glyphs = {
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.escape: 'Esc',
};

/// One line of the keyboard reference.
typedef ShortcutEntry = ({String keys, String action});

/// The whole keyboard reference: every player key from [playerShortcuts] —
/// so a shortcut added there shows up here by itself — then the two app-wide
/// keys that live outside that map by design: Escape (the `AppShell`
/// backstop, which works even when nothing is focused) and the Settings key
/// (the shell's handler and the menu bar's Settings… item, one door).
///
/// [mac] picks the modifier glyph. It is a platform CONVENTION, so callers
/// pass `defaultTargetPlatform == TargetPlatform.macOS`, not whether the
/// native runner exists.
List<ShortcutEntry> shortcutReference({required bool mac}) => [
  for (final entry in playerShortcuts.entries)
    (keys: keyGlyph(entry.key), action: playerShortcutLabel(entry.value)),
  (keys: 'Esc', action: 'Leave fullscreen'),
  (keys: mac ? '⌘ ,' : 'Ctrl ,', action: 'Settings'),
];
