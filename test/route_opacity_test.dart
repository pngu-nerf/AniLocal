import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// A pushed page must present as an OPAQUE frame from its first painted frame —
/// nothing from the page underneath showing through, in either direction.
///
/// Pages stopped carrying their own `Scaffold` when the header was hoisted (the
/// shell owns the only one), so nothing in a route paints an opaque background
/// of its own. `MaterialPageRoute` keeps a 300ms `transitionDuration` even when
/// the transition BUILDER draws nothing, and `TransitionRoute` marks the overlay
/// entry non-opaque for that whole window — so the library kept painting under
/// the arriving detail page for ~3 frames. `InstantPageRoute` zeroes the
/// duration so the entry is opaque immediately.
///
/// These finders rely on `skipOffstage` (true by default): an opaque top route
/// pushes everything below it OFFSTAGE, so finding the page below means it is
/// still being painted through.

Widget _page(String marker, String title) => SpecPage(
  spec: HeaderSpec(title: title),
  body: Text(marker),
);

Future<ShellHarness> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = ShellHarness();
  await tester.pumpWidget(h.app(home: _page('LIBRARY', 'Library')));
  await tester.pump();
  await tester.pump();
  return h;
}

void main() {
  testWidgets('a pushed page is opaque on its FIRST frame — the page below '
      'does not paint through', (tester) async {
    final h = await _pumpHome(tester);
    expect(find.text('LIBRARY'), findsOneWidget);

    h.push(_page('DETAIL', 'Detail'));
    await tester.pump();

    expect(
      find.text('DETAIL'),
      findsOneWidget,
      reason: 'the pushed page is up on frame 1',
    );
    expect(
      find.text('LIBRARY'),
      findsNothing,
      reason:
          'the page below must be offstage immediately — if it is still '
          'painting, its content composites under the arriving page for the '
          "length of the route's transition duration",
    );
  });

  testWidgets('and stays opaque — no bleed appears a few frames in', (
    tester,
  ) async {
    final h = await _pumpHome(tester);
    h.push(_page('DETAIL', 'Detail'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('LIBRARY'), findsNothing, reason: 'bleed at frame $i');
    }
  });

  testWidgets(
    'back-navigation is opaque too — the popped page does not linger',
    (tester) async {
      final h = await _pumpHome(tester);
      h.push(_page('DETAIL', 'Detail'));
      await tester.pump();
      expect(find.text('DETAIL'), findsOneWidget);

      h.pop();
      await tester.pump();

      expect(find.text('LIBRARY'), findsOneWidget);
      expect(
        find.text('DETAIL'),
        findsNothing,
        reason:
            'the popped page must be gone on the first frame back, not '
            'composited over the library while it fades',
      );
    },
  );
}
