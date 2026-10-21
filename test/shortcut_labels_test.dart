import 'package:anilocal/ui/theater/controls/player_shortcuts.dart';
import 'package:anilocal/ui/theater/controls/shortcut_labels.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keyboard reference in Settings › About is DERIVED from the player's key
/// map plus the two app-wide keys, so it cannot drift from what the keys do.
void main() {
  test('one line per player key, then Escape and the Settings key', () {
    final rows = shortcutReference(mac: true);
    expect(rows, hasLength(playerShortcuts.length + 2));
    expect(rows.last, (keys: '⌘ ,', action: 'Settings'));
    expect(rows[rows.length - 2], (keys: 'Esc', action: 'Leave fullscreen'));
    expect(shortcutReference(mac: false).last.keys, 'Ctrl ,');
  });

  test('the words carry the real step sizes', () {
    expect(
      playerShortcutLabel(PlayerShortcut.seekForward),
      'Forward ${kSeekStep.inSeconds} s',
    );
    expect(
      playerShortcutLabel(PlayerShortcut.volumeDown),
      'Volume down ${kVolumeStep.round()} %',
    );
  });

  test('keys are glyphs, not labels', () {
    expect(keyGlyph(LogicalKeyboardKey.space), 'Space');
    expect(keyGlyph(LogicalKeyboardKey.arrowRight), '→');
    // An unmapped key still says something.
    expect(keyGlyph(LogicalKeyboardKey.keyK), 'K');
  });
}
