import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the player's cursor-hide "wake-on-move" wiring (the
/// audit's fragile-machinery trap). It mirrors the EXACT overlay structure of
/// `_PlayerControlsState.build` — `Focus → Listener(translucent,
/// onPointerHover) → MouseRegion(cursor: visible ? basic : none) → Stack[opaque
/// GestureDetector]` — and drives a real mouse HOVER (move, no button) while
/// the region's cursor is hidden, asserting the wake logic still fires.
///
/// The invariant this locks in: reveal-on-move hangs off the **Listener above
/// the cursor MouseRegion** (`Listener.onPointerHover`), NOT the MouseRegion's
/// own `onHover` — so a mouse move brings the controls (and cursor) back
/// without a click. If someone moves the wake handler onto the MouseRegion,
/// this still passes in the tester (the widget tester can't reproduce the
/// engine-level `cursor:none` hover suppression), so this guards the *wiring
/// intent*, not the platform behavior — the real check is a visual wiggle in
/// fullscreen. Kept faithful to structure so it fails loudly if the overlay is
/// restructured in a way that stops delivering hover to the wake handler.
class _WakeHarness extends StatefulWidget {
  const _WakeHarness({super.key});

  @override
  State<_WakeHarness> createState() => _WakeHarnessState();
}

class _WakeHarnessState extends State<_WakeHarness> {
  bool visible = true;
  int wakeCount = 0;

  void _wake() {
    wakeCount++;
    if (!visible) setState(() => visible = true);
  }

  /// Simulate the idle-timer auto-hide (cursor → none).
  void hide() => setState(() => visible = false);

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // Wake-on-move on the Listener ABOVE the cursor MouseRegion.
        onPointerHover: (_) => _wake(),
        child: MouseRegion(
          cursor: visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onEnter: (_) => _wake(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'wake-on-move (Listener.onPointerHover) fires while the cursor is hidden — '
    'recovers visibility on a mouse move, no click',
    (tester) async {
      final key = GlobalKey<_WakeHarnessState>();
      const boxKey = Key('wake-harness-box');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: boxKey,
                width: 400,
                height: 300,
                child: _WakeHarness(key: key),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byKey(boxKey));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await tester.pump();

      // Auto-hide (idle while playing) → cursor none.
      key.currentState!.hide();
      await tester.pump();
      expect(
        key.currentState!.visible,
        isFalse,
        reason: 'precondition: hidden',
      );

      // Wiggle in place — the fullscreen recovery path (no rail to re-enter).
      final before = key.currentState!.wakeCount;
      await gesture.moveTo(center + const Offset(20, 10));
      await tester.pump();
      await gesture.moveTo(center + const Offset(-15, 25));
      await tester.pump();

      expect(
        key.currentState!.wakeCount,
        greaterThan(before),
        reason: 'a mouse move must reach the wake handler while cursor:none',
      );
      expect(key.currentState!.visible, isTrue, reason: 'controls recovered');
    },
  );
}
