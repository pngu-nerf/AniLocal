import 'package:anilocal/ui/widgets/xp_dialog.dart';
import 'package:anilocal/ui/shell/header_spec.dart';

import 'support/shell_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the "ListTile background color or ink splashes may be
/// invisible" framework warning: the instrument shells (`AppShell`'s chassis,
/// and [XpDialog]) must put content on a real [Material] (XpChassis)
/// so a `ListTile` inside them has a Material to paint on — NOT a bare
/// `ColoredBox` that hides the paint and trips the assert. The widget tester
/// records that assert as an exception, so a plain pump + `takeException()` is
/// the check; if either shell regresses to a `ColoredBox`, this fails.
void main() {
  testWidgets(
    'the app shell puts a ListTile on a Material (no ink-hidden warning)',
    (tester) async {
      await tester.pumpWidget(
        ShellHarness().app(
          home: SpecPage(
            spec: const HeaderSpec(title: 'X'),
            body: ListView(
              children: [ListTile(title: const Text('row'), onTap: () {})],
            ),
          ),
        ),
      );
      await tester.pump();
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
