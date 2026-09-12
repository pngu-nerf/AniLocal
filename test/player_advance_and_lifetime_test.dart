import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'support/recording_player.dart';

Widget _controls(RecordingPlayer player, {required VoidCallback playNext}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: PlayerControls(
            player: player,
            state: ValueNotifier(const PlayerControlsState()),
            actions: PlayerControlsActions(
              skipIntro: () {},
              skipOutro: () {},
              playNext: playNext,
              cancelPreRoll: () {},
              toggleFullscreen: () {},
            ),
          ),
        ),
      ),
    );

/// The bar's two lifetime contracts: a held key does not advance episodes,
/// and a bar that leaves the tree leaves the app-lifetime player alone.
void main() {
  testWidgets('seeking past the end advances on a PRESS, not on key repeat', (
    tester,
  ) async {
    var advances = 0;
    final player = RecordingPlayer(
      state: const PlayerState(
        duration: Duration(minutes: 24),
        position: Duration(minutes: 23, seconds: 55),
      ),
    );
    await tester.pumpWidget(_controls(player, playNext: () => advances++));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(advances, 1, reason: 'the press advances');
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(advances, 1, reason: 'a held → would skip an episode per repeat');
    expect(
      player.seeks,
      isEmpty,
      reason: 'nor does the repeat bounce the seek',
    );

    // Away from the end, repeats still seek — holding → scrubs as before.
    player.state = const PlayerState(
      duration: Duration(minutes: 24),
      position: Duration(minutes: 5),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(player.seeks, hasLength(2));
    await tester.pump(const Duration(seconds: 3)); // drain the auto-hide timer
  });

  testWidgets('the seek bar releases its player subscriptions on dispose', (
    tester,
  ) async {
    final player = RecordingPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SeekBar(player: player)),
      ),
    );
    expect(player.positionHasListener, isTrue);
    expect(player.durationHasListener, isTrue);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(
      player.positionHasListener,
      isFalse,
      reason:
          'the player outlives every theater visit; the bar must not '
          'leave a listener behind each time',
    );
    expect(player.durationHasListener, isFalse);
  });

  test('timeline markers are withheld when skipping is off', () {
    final intro = SkipRange(
      start: Duration.zero,
      end: const Duration(seconds: 90),
    );
    final episode = Episode(number: 1, fileRef: '/a.mkv', introSkip: intro);
    expect(
      PlayerControlsState(
        episode: episode,
        skipMode: SkipMode.button,
      ).introMarker,
      intro,
    );
    expect(
      PlayerControlsState(episode: episode, skipMode: SkipMode.off).introMarker,
      isNull,
    );
  });
}
