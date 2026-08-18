import 'package:anilocal/ui/shell/header_controller.dart';
import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:anilocal/ui/theme/xp_widgets.dart';
import 'package:anilocal/ui/widgets/header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// The hoisted header's CONTRACT — and specifically its silent-failure surface.
///
/// The header is now mounted once above the Navigator and fed by pages that
/// publish a spec. Everything that used to be impossible-by-construction (the
/// page built its own header, so it was always right) is now a data flow that
/// can go stale. These tests pin the ways it must NOT fail:
///  - a pop must restore the previous page's header,
///  - live state must keep flowing (or the scan spinner freezes),
///  - a missing spec must degrade per role — navigation available, information
///    neutral, actions absent (CLAUDE.md, "Fail toward user-in-control"),
///  - the readout's spinner must appear for genuine emptiness but NOT flash
///    during ordinary navigation,
///  - dialogs must not be mistaken for pages,
///  - and the header must genuinely not re-mount on navigation, which is the
///    whole point of the exercise.

Finder _spinnerGlyph() => find.byWidgetPredicate(
  (w) => w is VfdReadout && const ['-', '\\', '|', '/'].contains(w.text),
);

Finder _readoutText(String s) =>
    find.byWidgetPredicate((w) => w is VfdReadout && w.text == s);

/// A realistic window: the test font is far wider than the real one, so at the
/// 800x600 default the header's action tabs squeeze the readout and titles
/// marquee (rendering two copies) — which would break exact-match finders for
/// reasons that have nothing to do with the shell.
Future<void> _pumpShell(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
}

/// Past the grace window, so the spinner has had its chance to appear.
Future<void> _pumpPastGrace(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(
    HeaderController.spinnerGrace + const Duration(milliseconds: 50),
  );
}

void main() {
  testWidgets('A -> B -> back restores A\'s header exactly', (tester) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: SpecPage(
          spec: HeaderSpec(
            title: 'Library',
            actions: AppActions(
              scanning: false,
              unmatchedCount: 3,
              onFolders: () async {},
              onScan: () async {},
              onUnmatched: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpPastGrace(tester);
    expect(_readoutText('Library'), findsOneWidget);
    expect(find.byType(HeaderActionsBar), findsOneWidget);
    // Home: nothing to pop, so the back slot is reserved-but-invisible.
    expect(h.controller.canPop, isFalse);

    h.push(const SpecPage(spec: HeaderSpec(title: 'Detail')));
    await _pumpPastGrace(tester);
    expect(_readoutText('Detail'), findsOneWidget);
    expect(_readoutText('Library'), findsNothing);
    expect(find.byType(HeaderActionsBar), findsNothing, reason: 'B has none');
    expect(h.controller.canPop, isTrue);

    h.pop();
    await _pumpPastGrace(tester);
    expect(_readoutText('Library'), findsOneWidget, reason: 'A restored');
    expect(
      find.byType(HeaderActionsBar),
      findsOneWidget,
      reason:
          "A's actions must come back — the spec is route-keyed, so the "
          'restore is structural rather than a page remembering to republish',
    );
    expect(h.controller.canPop, isFalse);
    expect(_spinnerGlyph(), findsNothing);
  });

  testWidgets('live state keeps flowing — the scan spinner does not freeze', (
    tester,
  ) async {
    final h = ShellHarness();
    AppActions actions({required bool scanning}) => AppActions(
      scanning: scanning,
      unmatchedCount: 0,
      onFolders: () async {},
      onScan: () async {},
      onUnmatched: () {},
      onSettings: () {},
    );
    await _pumpShell(
      tester,
      h.app(
        home: SpecPage(
          spec: HeaderSpec(title: 'Library', actions: actions(scanning: false)),
        ),
      ),
    );
    await _pumpPastGrace(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Flip live state the way the real page does — setState, with NO
    // navigation and NO didUpdateWidget. A lifecycle-only publish would leave
    // the header frozen here.
    tester
        .state<SpecPageState>(find.byType(SpecPage))
        .update(HeaderSpec(title: 'Library', actions: actions(scanning: true)));
    await tester.pump();
    await tester.pump();
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'live state must reach the hoisted header',
    );
  });

  testWidgets('a page that publishes nothing degrades per role: back VISIBLE, '
      'title -> spinner, actions ABSENT', (tester) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: const SpecPage(spec: HeaderSpec(title: 'Library')),
      ),
    );
    await _pumpPastGrace(tester);

    h.push(const SilentPage());
    await _pumpPastGrace(tester);

    // NAVIGATION fails available — derived from canPop, never from the spec.
    expect(h.controller.canPop, isTrue);
    final back = tester.widget<XpTitleTab>(
      find
          .ancestor(
            of: find.byTooltip('Back'),
            matching: find.byType(XpTitleTab),
          )
          .first,
    );
    expect(back.onPressed, isNotNull, reason: 'never strand the user');

    // INFORMATION fails neutral — spinner, never the previous page's title.
    expect(_spinnerGlyph(), findsOneWidget);
    expect(_readoutText('Library'), findsNothing, reason: 'no stale title');

    // ACTIONS fail absent — a stale action would fire the wrong side effect.
    expect(find.byType(HeaderActionsBar), findsNothing);
  });

  testWidgets('the spinner does NOT flash during ordinary navigation', (
    tester,
  ) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: const SpecPage(spec: HeaderSpec(title: 'Library')),
      ),
    );
    await _pumpPastGrace(tester);

    h.push(const SpecPage(spec: HeaderSpec(title: 'Detail')));
    // Frame-by-frame across the whole transition: the incoming page publishes
    // well inside the grace window, so no frame may show the spinner.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _spinnerGlyph(),
        findsNothing,
        reason: 'spinner flashed mid-navigation at frame $i',
      );
    }
    await _pumpPastGrace(tester);
    expect(_readoutText('Detail'), findsOneWidget);
  });

  testWidgets('a dialog is not a page — the header is untouched behind it', (
    tester,
  ) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: const SpecPage(spec: HeaderSpec(title: 'Library')),
      ),
    );
    await _pumpPastGrace(tester);

    showDialog<void>(
      context: h.navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('hi')),
    );
    await _pumpPastGrace(tester);

    expect(
      _readoutText('Library'),
      findsOneWidget,
      reason:
          'a dialog route must not become "the top page" — the observer is '
          'typed to PageRoute precisely so the readout does not spin behind it',
    );
    expect(_spinnerGlyph(), findsNothing);
  });

  testWidgets('the header is MOUNTED ONCE — navigation does not re-mount it', (
    tester,
  ) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: const SpecPage(spec: HeaderSpec(title: 'Library')),
      ),
    );
    await _pumpPastGrace(tester);
    final before = tester.element(find.byType(XpTitleBar));

    h.push(const SpecPage(spec: HeaderSpec(title: 'Detail')));
    await _pumpPastGrace(tester);
    h.pop();
    await _pumpPastGrace(tester);

    expect(
      tester.element(find.byType(XpTitleBar)),
      same(before),
      reason:
          'the whole point: the header lives above the Navigator, so a '
          'push/pop must not rebuild it',
    );
  });

  testWidgets('a chromeless route collapses the shell chrome (no double '
      'header for the theater)', (tester) async {
    final h = ShellHarness();
    await _pumpShell(
      tester,
      h.app(
        home: const SpecPage(spec: HeaderSpec(title: 'Library')),
      ),
    );
    await _pumpPastGrace(tester);
    expect(find.byType(XpTitleBar), findsOneWidget);

    h.pushChromeless(const SilentPage());
    await _pumpPastGrace(tester);
    expect(
      find.byType(XpTitleBar),
      findsNothing,
      reason:
          'the theater draws its own header; the shell must not stack a '
          'second one above it',
    );
    expect(_spinnerGlyph(), findsNothing, reason: 'and must not spin either');
  });
}
