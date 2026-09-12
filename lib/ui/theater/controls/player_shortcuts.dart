import 'package:flutter/services.dart';

/// What a player key does. The table below maps keys onto these; the handler
/// in `PlayerControls` dispatches on the value. Adding a shortcut is one row
/// here and one case there — the key→action mapping is data, not an if-chain.
enum PlayerShortcut { playPause, seekForward, seekBack, volumeUp, volumeDown }

/// How far ←/→ move.
const Duration kSeekStep = Duration(seconds: 10);

/// How far ↑/↓ move the volume, in percent.
const double kVolumeStep = 5;

/// The player's key map. (A `final` map, not `const`: [LogicalKeyboardKey]
/// overrides `==`, which a constant map's keys may not.)
///
/// Escape is deliberately ABSENT. It exits fullscreen from ONE place — the
/// app-wide backstop in `AppShell`, which runs before focus dispatch and so
/// works even when nothing is focused (the state this player has historically
/// fallen into). Listing it here as well would be dead code that looks
/// load-bearing.
final Map<LogicalKeyboardKey, PlayerShortcut> playerShortcuts = {
  LogicalKeyboardKey.space: PlayerShortcut.playPause,
  LogicalKeyboardKey.arrowRight: PlayerShortcut.seekForward,
  LogicalKeyboardKey.arrowLeft: PlayerShortcut.seekBack,
  LogicalKeyboardKey.arrowUp: PlayerShortcut.volumeUp,
  LogicalKeyboardKey.arrowDown: PlayerShortcut.volumeDown,
};
