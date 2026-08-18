import 'package:anilocal/ui/library/library_layout.dart';
import 'package:anilocal/ui/library/library_layout_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The continue-watching panel is sized in POINTS, not as a fraction of the
/// window. Both bugs this replaces came from the fraction:
///  - it rescaled the panel on every window resize, and
///  - "clamped at the minimum fraction" guaranteed no real width, so a small
///    window left an unreadable sliver.

const Key _panelKey = Key('panel');
const Key _gridKey = Key('grid');

Widget _layout({required double panelWidth, bool collapsed = false}) =>
    MaterialApp(
      home: Scaffold(
        body: LibraryLayout(
          config: LibraryLayoutConfig(
            panelWidth: panelWidth,
            panelCollapsed: collapsed,
          ),
          onPanelResize: (_) {},
          zones: const {
            LibraryZone.continueWatching: SizedBox.expand(key: _panelKey),
            LibraryZone.grid: SizedBox.expand(key: _gridKey),
          },
        ),
      ),
    );

Future<void> _pumpAt(WidgetTester tester, Widget app, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
}

void main() {
  testWidgets('the panel keeps its width as the window resizes — the GRID '
      'absorbs the change', (tester) async {
    const w = 300.0;
    final widths = <double>[];
    final gridWidths = <double>[];

    // Every size at or above the app's enforced 600pt minimum window.
    for (final windowWidth in <double>[1512, 1100, 800, 600]) {
      await _pumpAt(tester, _layout(panelWidth: w), windowWidth);
      widths.add(tester.getSize(find.byKey(_panelKey)).width);
      gridWidths.add(tester.getSize(find.byKey(_gridKey)).width);
    }

    expect(
      widths,
      everyElement(w),
      reason:
          'the panel must be $w at every window size — a fraction would '
          'have given four different widths',
    );
    // …and the grid is what actually changed.
    expect(gridWidths.toSet().length, gridWidths.length);
  });

  testWidgets('the minimum is a REAL width at the tightest window', (
    tester,
  ) async {
    // The old failure: 0.15 "at minimum" was ~90pt in a 600pt window.
    await _pumpAt(
      tester,
      _layout(panelWidth: LibraryLayoutConfig.panelWidthMin),
      600,
    );
    final panel = tester.getSize(find.byKey(_panelKey)).width;
    expect(panel, LibraryLayoutConfig.panelWidthMin);
    expect(panel, greaterThanOrEqualTo(220));
    // …and the grid still has usable room beside it.
    expect(
      tester.getSize(find.byKey(_gridKey)).width,
      greaterThanOrEqualTo(360),
    );
  });

  testWidgets('the widest panel still fits the tightest window', (
    tester,
  ) async {
    // panelWidthMax + the layout's grid floor is exactly the 600pt minimum
    // window, so the safety clamp must NOT bite here: the panel keeps its width.
    await _pumpAt(
      tester,
      _layout(panelWidth: LibraryLayoutConfig.panelWidthMax),
      600,
    );
    expect(
      tester.getSize(find.byKey(_panelKey)).width,
      LibraryLayoutConfig.panelWidthMax,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('below the enforced minimum window it degrades instead of '
      'overflowing', (tester) async {
    // Only reachable in tests — the runner enforces 600 — but it must not hand
    // the grid a negative width.
    await _pumpAt(tester, _layout(panelWidth: 480), 380);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_gridKey)).width, greaterThan(0));
  });

  testWidgets('collapsed is still a fixed thin strip', (tester) async {
    await _pumpAt(tester, _layout(panelWidth: 300, collapsed: true), 1100);
    expect(
      tester.getSize(find.byKey(_panelKey)).width,
      LibraryLayoutConfig.landingDefault.collapsedPanelWidth,
    );
  });
}
