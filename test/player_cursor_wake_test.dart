import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Regression guard for the player's cursor-hide "wake-on-move" wiring — the
/// fragile-machinery trap the maintainability assessment flagged (the OLD test
/// here was a false-positive: it mirrored the structure in a private harness and
/// passed even under its own regression).
///
/// The bug it guards against: reveal-on-move being (re)attached to the cursor
/// MouseRegion's own `onHover` instead of the `Listener.onPointerHover` ABOVE
/// it. A `MouseRegion` whose cursor is `SystemMouseCursors.none` stops delivering
/// `onHover` at the engine level, so wake would silently die and cursor recovery
/// would degrade to a click (the reported bug). The fix lives at
/// `player_control_bar.dart` (see the long comment there) and the player
/// regression checklist.
///
/// HOW this test is genuine (vs the old one): it pumps the REAL `PlayerControls`
/// widget (via a native-free stand-in [Player] — see [_FakePlayer]) and asserts
/// the production widget tree's shape:
///   • the wake handler is on a `Listener.onPointerHover`, AND
///   • the cursor-hiding `MouseRegion` directly under it carries NO `onHover`.
/// Moving the wake onto the MouseRegion flips BOTH: the wake `Listener`
/// disappears (its `onPointerHover` goes null) and the cursor MouseRegion gains
/// an `onHover`. Either assertion then fails. (Verified: building the regression
/// shape makes both finders flip.)
///
/// WHAT stays manual-verify: the engine-level fact that `cursor: none` suppresses
/// `MouseRegion.onHover` is NOT reproduced by the widget tester (it delivers
/// hover to a MouseRegion regardless of cursor). So this test locks the WIRING
/// (which is what a maintainer would "clean up"); the platform suppression itself
/// is confirmed by a fullscreen wiggle on device (regression checklist §C/§D).

const Stream<Never> _empty = Stream<Never>.empty();

/// A no-native stand-in for media_kit's [Player]: the harness can't construct a
/// real one (libmpv/`Mpv.framework` is absent in `flutter test`), so this
/// supplies a real [PlayerState] and real (empty) [PlayerStream] — everything
/// the controls read at build time — and `noSuchMethod` swallows the rest
/// (seek/playOrPause/… only fire on interaction, never during a structural
/// pump).
class _FakePlayer implements Player {
  _FakePlayer({bool playing = false}) : state = PlayerState(playing: playing);

  @override
  final PlayerState state;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(Player player) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      // Wide enough that the bar lays out non-compact (no folded controls) —
      // keeps the tree stable and unambiguous.
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

/// The single wake `Listener`: the one carrying BOTH `onPointerHover` (wake) and
/// `onPointerDown` (focus reclaim) — the overlay Listener in `PlayerControls`.
final _wakeListener = find.byWidgetPredicate(
  (w) => w is Listener && w.onPointerHover != null && w.onPointerDown != null,
);

/// The cursor-hiding overlay MouseRegion: the nearest `MouseRegion` under the
/// wake Listener (production: `Listener → MouseRegion → Stack`).
Finder get _overlayRegion => find
    .descendant(of: _wakeListener, matching: find.byType(MouseRegion))
    .first;

void main() {
  testWidgets(
    'STRUCTURAL: wake-on-move is on Listener.onPointerHover, NOT the cursor '
    'MouseRegion (fails if the wake is moved onto the MouseRegion)',
    (tester) async {
      await tester.pumpWidget(_app(_FakePlayer()));

      // Wake lives on a Listener — exactly one, and it also reclaims focus.
      expect(
        _wakeListener,
        findsOneWidget,
        reason:
            'reveal-on-move must hang off Listener.onPointerHover (above the '
            'cursor MouseRegion). If it were moved onto the MouseRegion, no '
            'Listener would carry onPointerHover and this finds nothing.',
      );

      // The cursor MouseRegion directly under it must NOT carry the wake: a
      // cursor:none MouseRegion stops firing onHover, which is the whole bug.
      final region = tester.widget<MouseRegion>(_overlayRegion);
      expect(
        region.onHover,
        isNull,
        reason:
            'the cursor-hiding MouseRegion must not carry wake-on-move '
            '(onHover) — it goes dead under cursor:none. Wake belongs on the '
            'Listener above it.',
      );
      // Sanity: it IS the cursor region (toggling cursor + windowed re-entry).
      expect(region.onEnter, isNotNull);
      expect(region.cursor, SystemMouseCursors.basic); // visible at rest
    },
  );

  testWidgets(
    'BEHAVIORAL: idle auto-hide drops the cursor to none, then a mouse MOVE '
    '(no click) via the wake path brings it back',
    (tester) async {
      // playing:true so the 3s idle timer actually hides (it only hides while
      // playing — a paused player keeps controls, by design).
      await tester.pumpWidget(_app(_FakePlayer(playing: true)));

      MouseCursor cursor() => tester.widget<MouseRegion>(_overlayRegion).cursor;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(PlayerControls));
      // Enter the overlay → _show() → controls visible + 3s idle timer armed.
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await tester.pump();
      expect(cursor(), SystemMouseCursors.basic, reason: 'visible at rest');

      // Idle while playing → auto-hide → cursor none.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        cursor(),
        SystemMouseCursors.none,
        reason: 'controls (and cursor) auto-hide after idle while playing',
      );

      // A bare MOVE (hover, no button) must recover — this is the fullscreen
      // in-place recovery. (This exercises the wake loop end-to-end; it does
      // NOT distinguish Listener-vs-MouseRegion wiring — the tester delivers
      // hover either way — which is exactly why the STRUCTURAL test above is
      // the real guard.)
      await gesture.moveTo(center + const Offset(24, 12));
      await tester.pump();
      expect(
        cursor(),
        SystemMouseCursors.basic,
        reason: 'a mouse move brings controls + cursor back, no click needed',
      );
    },
  );
}
