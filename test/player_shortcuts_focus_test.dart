import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Regression guard for the player's keyboard-shortcut FOCUS OWNERSHIP — the
/// fragile machinery the maintainability assessment found untested. The overlay
/// (`PlayerControls`) OWNS a FocusNode (`autofocus:true`, reclaimed on
/// interaction) so shortcuts keep working, and wraps the control bar in
/// `Focus(canRequestFocus:false, descendantsAreFocusable:false)` so a focused
/// slider/button can't swallow space/←/→. A maintainer "simplifying" that to a
/// one-shot autofocus, or dropping the bar's focus-free wrapper, silently kills
/// keyboard control — with a green suite, until now.
///
/// Genuine because it pumps the REAL `PlayerControls` (native-free stand-in
/// [_RecordingPlayer]) and (1) sends real key events that must reach the player
/// through the owned focus and delegate to the SAME player methods the buttons
/// use, and (2) asserts the bar's focus-free wrapper is actually there.
///
/// Manual-verify remainder: focus RECLAIM after returning from the live
/// fullscreen route can't be driven here (no real fullscreen route in the
/// harness) — that path is on the regression checklist (§D).

const Stream<Never> _empty = Stream<Never>.empty();

/// Stand-in [Player] that RECORDS the methods the shortcut handler calls (via
/// noSuchMethod) and serves a real state/streams so the controls build.
class _RecordingPlayer implements Player {
  final List<Invocation> calls = [];

  @override
  final PlayerState state = const PlayerState(); // volume 100, duration 0

  @override
  final PlayerStream stream = const PlayerStream(
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
  );

  bool called(Symbol member) => calls.any((c) => c.memberName == member);
  Invocation lastCall(Symbol member) =>
      calls.lastWhere((c) => c.memberName == member);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) calls.add(invocation);
    // The player methods the shortcut handler calls (playOrPause/setVolume/seek)
    // return Future<void>; the noSuchMethod forwarder type-checks the return, so
    // hand back a Future (null would throw a TypeError after recording).
    return Future<void>.value();
  }
}

Widget _app(Player player) => MaterialApp(
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
          playNext: () {},
          cancelPreRoll: () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'shortcuts reach the player through the OWNED focus and delegate to the '
    'same player paths the on-screen controls use',
    (tester) async {
      final player = _RecordingPlayer();
      await tester.pumpWidget(_app(player));
      await tester.pump(); // let autofocus settle

      // No manual focusing: if the overlay didn't own+autofocus its node, these
      // keys would go unhandled and nothing would be recorded.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(
        player.called(#playOrPause),
        isTrue,
        reason: 'space → playOrPause',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(player.called(#setVolume), isTrue, reason: '↑ → setVolume');
      // volume 100 + 5, clamped to 100.
      expect(player.lastCall(#setVolume).positionalArguments.first, 100.0);

      player.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(
        player.lastCall(#setVolume).positionalArguments.first,
        95.0,
        reason: '↓ → setVolume(volume-5)',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(player.called(#seek), isTrue, reason: '← → seek (∓10s)');

      player.calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(player.called(#seek), isTrue, reason: '→ → seek (∓10s)');

      // Each key calls _show(), which arms a 3s auto-hide timer; drain it so no
      // timer is pending at teardown.
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'the player overlay owns primary focus, and the control bar is wrapped so '
    'it can NEVER hold keyboard focus',
    (tester) async {
      await tester.pumpWidget(_app(_RecordingPlayer()));
      await tester.pump();

      // The owned focus node (the Focus with the key handler) has primary focus
      // after autofocus — this is what makes shortcuts land without a click.
      final ownerFocus = tester.widget<Focus>(
        find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'AniLocal player',
        ),
      );
      expect(
        ownerFocus.focusNode?.hasPrimaryFocus,
        isTrue,
        reason: 'the player overlay owns + holds keyboard focus',
      );

      // The bar's wrapper: canRequestFocus:false AND descendantsAreFocusable:
      // false — so no button/slider inside the bar can steal space/←/→. This is
      // the exact guard; dropping either flag reintroduces the focus-steal bug.
      final barWrapper = find.byWidgetPredicate(
        (w) =>
            w is Focus &&
            w.canRequestFocus == false &&
            w.descendantsAreFocusable == false,
      );
      expect(barWrapper, findsOneWidget);
      // It really is the bar's wrapper (an ancestor of the control bar).
      expect(
        find.descendant(
          of: barWrapper,
          matching: find.byType(PlayerControlBar),
        ),
        findsOneWidget,
      );
    },
  );
}
