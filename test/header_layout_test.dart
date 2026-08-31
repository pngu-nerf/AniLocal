import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anilocal/ui/theme/brand_wordmark.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:anilocal/ui/theme/xp_tokens.dart';
import 'package:anilocal/ui/theme/xp_widgets.dart';
import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:anilocal/ui/widgets/header_actions.dart';
import 'package:anilocal/ui/window_chrome.dart';

import 'support/shell_harness.dart';

/// A show title long enough to overflow the screen at a narrow window but not
/// at a wide one — which is what makes "fit is decided against the CURRENT
/// width" testable with one string. (The dot-matrix is painted, so its width is
/// exactly `12·chars − 2` at the header's pitch, independent of the test font.)
const String _title = 'Dragon Ball Z Battle of Gods';

/// The shared header shell's LAYOUT contract — the part that is easy to break
/// by nudging a padding somewhere and impossible to eyeball at every width:
///
/// 1. the VFD screen is centred on the WINDOW's horizontal midpoint, with equal
///    empty space to each window edge, at every width;
/// 2. it clears both button clusters (no overlap, no overflow);
/// 3. which cluster constrains it FLIPS at the tab label/icon collapse, and it
///    stays centred straight through that transition;
/// 4. home reserves the back slot, so the screen sits identically on home and
///    on a pushed screen;
/// 5. the title centres when it fits the CURRENT width and marquees when it
///    doesn't;
/// 6. branding is on the chassis, not in the screen.
///
/// Note the readout's dot-matrix is painted, not typeset, so its measurements
/// are font-independent; the CHROME tab labels are not, and the test font is
/// wider than the real one, so the assertions below are about relationships
/// (symmetry, ordering, no overlap) rather than absolute pixel widths.
/// The header is hoisted now, so a "screen" is the shell plus a page that
/// publishes a spec. `showBack` maps to whether a second route is pushed —
/// back visibility is derived from the navigator's canPop, not from the spec.
late ShellHarness _harness;

HeaderSpec _spec({int unmatched = 0, String title = 'Library'}) => HeaderSpec(
  title: title,
  actions: AppActions(
    scanning: false,
    unmatchedCount: unmatched,
    onUnmatched: () {},
    onScan: () async {},
    onSettings: () {},
  ),
);

Widget _screen({int unmatched = 0, String title = 'Library'}) {
  _harness = ShellHarness();
  return _harness.app(
    home: SpecPage(
      spec: _spec(unmatched: unmatched, title: title),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Widget app, double width) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  // Bounded pumps, never pumpAndSettle: a scrolling title never settles. Two
  // pumps: the page publishes its spec on its first build, and the hoisted
  // header renders it on the following frame.
  await tester.pump();
  await tester.pump();
}

/// Right edge of the left cluster (traffic-light inset + brand + back slot).
double _leftClusterEdge(WidgetTester tester) =>
    tester.getRect(find.byTooltip('Back')).right;

/// Left edge of the right cluster (the action tabs).
double _rightClusterEdge(WidgetTester tester) =>
    tester.getRect(find.byType(HeaderActionsBar)).left;

void main() {
  group('the VFD screen is centred on the window', () {
    // Wide (labelled tabs), medium, and narrow (icon-only tabs) — the acid test.
    for (final width in <double>[1440, 1100, 900, 800, 700, 600]) {
      testWidgets('symmetric and clear of both clusters at ${width}px', (
        tester,
      ) async {
        await _pumpAt(tester, _screen(), width);
        final screen = tester.getRect(find.byType(HeaderReadout));

        // (1) Equal empty space from each window edge — the whole point. Not
        // "fills the gap": the clusters differ in width, so gap-filling would
        // land the screen off-centre.
        expect(
          screen.left,
          moreOrLessEquals(width - screen.right, epsilon: 0.5),
          reason: 'screen is off-centre at ${width}px',
        );

        // (2) Clear of both clusters, and inside the window.
        expect(screen.left, greaterThanOrEqualTo(_leftClusterEdge(tester)));
        expect(screen.right, lessThanOrEqualTo(_rightClusterEdge(tester)));
        expect(screen.left, greaterThanOrEqualTo(0));
        expect(screen.right, lessThanOrEqualTo(width));
      });
    }

    testWidgets('is comfortably wide when the window has room', (tester) async {
      await _pumpAt(tester, _screen(), 1440);
      expect(
        tester.getRect(find.byType(HeaderReadout)).width,
        greaterThan(200),
      );
    });
  });

  testWidgets('the screen stays centred and clear across the label collapse', (
    tester,
  ) async {
    // The centring is symmetric about the WINDOW, so whichever cluster is
    // wider sets the half-width — and which one that is changes with the tab
    // labels (and with the font: the test font is wider than the real one, so
    // this asserts the relationship, never which side happens to win).

    // Just above the threshold: labelled tabs.
    await _pumpAt(tester, _screen(), Xp.headerLabelWidth + 1);
    final labelled = tester.getRect(find.byType(HeaderReadout));
    expect(
      labelled.left,
      moreOrLessEquals(Xp.headerLabelWidth + 1 - labelled.right, epsilon: 0.5),
    );
    expect(labelled.left, greaterThanOrEqualTo(_leftClusterEdge(tester)));
    expect(labelled.right, lessThanOrEqualTo(_rightClusterEdge(tester)));

    // Just below: the tabs collapse to icons, the constraint can swap sides,
    // and the screen must still be centred and clear of BOTH clusters.
    await _pumpAt(tester, _screen(), Xp.headerLabelWidth - 1);
    final icons = tester.getRect(find.byType(HeaderReadout));
    expect(
      icons.left,
      moreOrLessEquals(Xp.headerLabelWidth - 1 - icons.right, epsilon: 0.5),
      reason: 'the screen must stay centred through the collapse',
    );
    expect(icons.left, greaterThanOrEqualTo(_leftClusterEdge(tester)));
    expect(icons.right, lessThanOrEqualTo(_rightClusterEdge(tester)));
  });

  testWidgets('home reserves the back slot, so the screen does not shift', (
    tester,
  ) async {
    await _pumpAt(tester, _screen(), 700);
    final noBack = tester.getRect(find.byType(HeaderReadout));

    // Push a second page: back becomes real, the readout must not move.
    _harness.push(const SpecPage(spec: HeaderSpec(title: 'Pushed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final withBack = tester.getRect(find.byType(HeaderReadout));
    expect(withBack, noBack);

    // Back on home is the real tab, laid out but neither painted nor
    // hit-testable — that's what makes it exactly the right width.
    _harness.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final reserved = tester.widget<Visibility>(
      find
          .ancestor(
            of: find.byTooltip('Back'),
            matching: find.byType(Visibility),
          )
          .first,
    );
    expect(reserved.visible, isFalse);
    expect(reserved.maintainSize, isTrue);
  });

  group('the title fits or scrolls against the CURRENT screen width', () {
    // The marquee runs two copies of the text as a conveyor, so a scrolling
    // title renders the readout twice; a static one, once.
    Finder readouts(String title) =>
        find.byWidgetPredicate((w) => w is VfdReadout && w.text == title);

    testWidgets('centred and static when it fits', (tester) async {
      await _pumpAt(tester, _screen(title: _title), 1440);
      expect(readouts(_title), findsOneWidget);
      final screen = tester.getRect(find.byType(HeaderReadout));
      final text = tester.getRect(readouts(_title));
      expect(
        text.center.dx,
        moreOrLessEquals(screen.center.dx, epsilon: 0.5),
        reason: 'a title that fits is centred in the screen',
      );
    });

    testWidgets('scrolls once the window narrows past its fit point', (
      tester,
    ) async {
      await _pumpAt(tester, _screen(title: _title), 600);
      expect(readouts(_title), findsNWidgets(2));
      // …and stays clipped to the black screen, never spilling onto the chrome.
      final screen = tester.getRect(find.byType(HeaderReadout));
      expect(screen.right, lessThanOrEqualTo(_rightClusterEdge(tester)));
    });
  });

  group('branding is chassis, not screen', () {
    testWidgets('the brand mark sits between the traffic lights and the '
        'back slot, and nothing lit says AniLocal', (tester) async {
      await _pumpAt(tester, _screen(), 1100);
      final brand = tester.getRect(find.byType(BrandWordmark));
      expect(brand.left, greaterThanOrEqualTo(kTrafficLightInset));
      expect(brand.right, lessThanOrEqualTo(_leftClusterEdge(tester)));
      expect(
        brand.right,
        lessThanOrEqualTo(tester.getRect(find.byType(HeaderReadout)).left),
      );
      // The wordmark is no longer a dot-matrix readout — that role is the
      // screen's alone now.
      expect(
        find.byWidgetPredicate((w) => w is VfdReadout && w.text == 'AniLocal'),
        findsNothing,
      );
    });

    testWidgets('the brand is the app\'s only serif, and it is not lit', (
      tester,
    ) async {
      await _pumpAt(tester, _screen(), 1100);
      final mark = tester.widget<Text>(
        find.descendant(
          of: find.byType(BrandWordmark),
          matching: find.byType(Text),
        ),
      );
      expect(mark.style!.fontFamily, Xp.brandFontFamily);
      expect(mark.style!.fontFamily, isNot(Xp.fontFamily));
      // Molded, not lit: a chrome ramp across the faces + a shadow pair for the
      // relief, and no phosphor colour anywhere near it.
      expect(mark.style!.foreground?.shader, isNotNull);
      expect(mark.style!.shadows, hasLength(2));
      expect(mark.style!.color, isNull);
    });

    testWidgets('the wordmark contracts to its initials on the SAME signal '
        'that collapses the tabs', (tester) async {
      String markText() => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(BrandWordmark),
              matching: find.byType(Text),
            ),
          )
          .data!;

      Iterable<bool> tabsLabelled() => tester
          .widgetList<XpTitleTab>(find.byType(XpTitleTab))
          .map((t) => t.showLabel);

      await _pumpAt(tester, _screen(), Xp.headerLabelWidth + 1);
      expect(markText(), BrandWordmark.text);
      expect(tabsLabelled(), everyElement(isTrue));

      await _pumpAt(tester, _screen(), Xp.headerLabelWidth - 1);
      expect(markText(), BrandWordmark.shortText);
      expect(
        tabsLabelled(),
        everyElement(isFalse),
        reason: 'the brand and every tab must contract together, not in stages',
      );
    });
  });

  testWidgets('the VFD screen is part of the window chrome (drag + '
      'double-click-to-zoom), not an inert panel', (tester) async {
    await _pumpAt(tester, _screen(), 1100);
    // The screen is wrapped in the SAME WindowDragArea the bare chassis uses,
    // so it carries both behaviours (move on pan, zoom on double-tap) rather
    // than depending on every widget inside it staying pointer-transparent.
    final drag = find.ancestor(
      of: find.byType(HeaderReadout),
      matching: find.byType(WindowDragArea),
    );
    expect(drag, findsOneWidget);
    final gesture = tester.widget<GestureDetector>(
      find.descendant(of: drag, matching: find.byType(GestureDetector)).first,
    );
    expect(gesture.onDoubleTap, isNotNull);
    expect(gesture.onPanStart, isNotNull);
    // …and it really is hit-testable there, not covered by a button cluster.
    expect(
      tester.hitTestOnBinding(
        tester.getRect(find.byType(HeaderReadout)).center,
      ),
      isNotNull,
    );
  });

  testWidgets('the theater header is the shared header, in its standard '
      'layout', (tester) async {
    // The theater mounts XpTitleBar in its own shell (a Scaffold appBar, NOT
    // XpWindow) — that shell is deliberately separate and untouched. What this
    // locks is that the header CONTENT it mounts is the ordinary shared one:
    // same serif brand mark, same window-centred screen, no bespoke variant.
    // Built directly here because libmpv can't run in the harness.
    await _pumpAt(
      tester,
      const MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(Xp.titleBarHeight),
            child: XpTitleBar(
              caption: _title,
              captionWidget: HeaderReadout(title: _title),
            ),
          ),
          body: SizedBox.shrink(),
        ),
      ),
      1100,
    );
    expect(find.byType(BrandWordmark), findsOneWidget);
    final screen = tester.getRect(find.byType(HeaderReadout));
    expect(
      screen.left,
      moreOrLessEquals(1100 - screen.right, epsilon: 0.5),
      reason: 'the player header centres its screen like every other screen',
    );
    // No frame inset in this shell, so the bar spans the whole window — the
    // centring maths must land on the window midpoint either way.
    expect(screen.center.dx, moreOrLessEquals(550, epsilon: 0.5));
  });
}
