import 'package:anilocal/ui/widgets/xp_dialog.dart';
import 'package:anilocal/ui/widgets/xp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the "ListTile background color or ink splashes may be
/// invisible" framework warning: the instrument shells ([XpWindow] via
/// [XpScreen], and [XpDialog]) must put content on a real [Material] (XpChassis)
/// so a `ListTile` inside them has a Material to paint on — NOT a bare
/// `ColoredBox` that hides the paint and trips the assert. The widget tester
/// records that assert as an exception, so a plain pump + `takeException()` is
/// the check; if either shell regresses to a `ColoredBox`, this fails.
void main() {
  testWidgets(
    'XpScreen puts a ListTile on a Material (no ink-hidden warning)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: XpScreen(
            title: 'X',
            child: ListView(
              children: [ListTile(title: const Text('row'), onTap: () {})],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'XpDialog puts a ListTile on a Material (no ink-hidden warning)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: XpDialog(
              title: 'X',
              content: ListTile(title: const Text('row'), onTap: () {}),
              actions: const [Text('ok')],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
