import 'package:anilocal/ui/tooltip_dismiss_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the fullscreen-exit crash whose ORIGINATING error was
/// `overlay.dart` `size == theater.size` (the `_dependents.isEmpty` assert and
/// the ~100k-px RenderFlex overflow that followed were downstream cascade).
///
/// Cause: a Tooltip mounted when fullscreen exits keeps a deferred
/// `OverlayPortal` child that re-lays-out against the now-stale overlay size as
/// the window resizes, and asserts. media_kit drives fullscreen enter/exit as a
/// ROOT-navigator push/pop — INCLUDING the macOS green traffic-light / native
/// exit (via its PopScope) — so [TooltipDismissingRouteObserver] dismisses
/// tooltips on every transition, covering ⛶, Escape, AND native exit in one
/// place.
///
/// This covers the OVERLAY/TOOLTIP path (distinct from the old non-subscribe /
/// `_dependents` test) and specifically the NATIVE-exit path (a route pop). The
/// live media_kit fullscreen route can't be driven in a widget test, so we
/// invoke the observer's transition callbacks directly — they're exactly what
/// the root navigator calls on push/pop — with a tooltip mounted, and assert it
/// gets cleared (so nothing remains to re-lay-out during the resize).
void main() {
  testWidgets(
    'route observer clears a mounted tooltip on pop (native exit) and push (enter)',
    (tester) async {
      final observer = TooltipDismissingRouteObserver();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Tooltip(
                message: 'Exit fullscreen',
                child: SizedBox(width: 24, height: 24),
              ),
            ),
          ),
        ),
      );
      final tip = tester.state<TooltipState>(find.byType(Tooltip));
      final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());

      Future<void> showTip() async {
        tip.ensureTooltipVisible();
        await tester.pump();
        expect(find.text('Exit fullscreen'), findsOneWidget);
      }

      // didPop == the native green-button exit: media_kit pops the fullscreen
      // route through the root navigator, which this observer watches.
      await showTip();
      observer.didPop(route, route);
      await tester.pump();
      expect(find.text('Exit fullscreen'), findsNothing);

      // didPush == fullscreen ENTER (also resizes the window).
      await showTip();
      observer.didPush(route, route);
      await tester.pump();
      expect(find.text('Exit fullscreen'), findsNothing);

      // didReplace / didRemove are covered by the same one-line dismiss.
      await showTip();
      observer.didReplace(newRoute: route, oldRoute: route);
      await tester.pump();
      expect(find.text('Exit fullscreen'), findsNothing);
    },
  );
}
