import 'package:anilocal/ui/settings/panels/sources_panel.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/settings_window.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_settings.dart';
import 'support/fake_sources.dart';

/// Sources moved out of its own page and into the settings window. This pins
/// what the relocation must not have cost: the list, add, remove and — the one
/// that silently degrades — drag-to-reorder still writing the priority order
/// through `reorderFolders`.
///
/// Order is not cosmetic. It is what `_logicalEpisodes` reads to decide which
/// copy of a duplicated episode plays, so a panel that renders a draggable list
/// without persisting the drag would look completely correct and change
/// nothing.

/// Filled when the window closes — the window is still open when [_open]
/// returns, so the outcome can only be read after Done.
class _Closed {
  SettingsOutcome? outcome;
}

Future<_Closed> _open(
  WidgetTester tester,
  FakeSourcesRepository repo, {
  Future<({bool added, String? deniedLabel})> Function()? onAddFolder,
}) async {
  tester.view.physicalSize = const Size(1200, 820);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final closed = _Closed();
  await tester.pumpWidget(
    MaterialApp(
      theme: XpTheme.data(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => closed.outcome = await showAppSettingsDialog(
              context,
              settings: const FakeSettings(),
              actions: SettingsDialogActions(
                sources: fakeSourcesActions(repo, onAddFolder: onAddFolder),
                onRefreshMetadata: () async =>
                    (seriesRefreshed: 0, skipsFetched: 0),
                onRefreshed: () {},
                loadUnmatchedCount: () async => 0,
                onOpenUnmatched: () {},
              ),
              initialCategory: sourcesCategoryId,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return closed;
}

/// Drag the row at [from] onto the row at [to] via its drag handle.
///
/// Moved in steps rather than one jump: `ReorderableListView` decides where an
/// item lands from the drag's running position, and a single teleport can be
/// consumed without ever crossing the target's midpoint.
Future<void> _dragRow(WidgetTester tester, int from, int to) async {
  final handles = find.byIcon(Icons.drag_handle);
  final start = tester.getCenter(handles.at(from));
  final target = tester.getCenter(handles.at(to));
  final drag = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 200));
  // Overshoot slightly so the pointer is clearly past the target's midpoint.
  final total = (target.dy - start.dy) * 1.2;
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await drag.moveBy(Offset(0, total / steps));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await drag.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Sources tab lists the folders in priority order', (
    tester,
  ) async {
    await _open(tester, FakeSourcesRepository(['/media/A', '/media/B']));

    expect(find.text('/media/A'), findsOneWidget);
    expect(find.text('/media/B'), findsOneWidget);
    expect(
      find.text('Preferred source'),
      findsOneWidget,
      reason: 'only the top folder is marked preferred',
    );
    expect(
      tester.getTopLeft(find.text('/media/A')).dy,
      lessThan(tester.getTopLeft(find.text('/media/B')).dy),
      reason: 'top of the list is highest priority',
    );
  });

  testWidgets(
    'dragging a source persists the new priority order — the play-priority '
    'the reorder drives, not just the visual order',
    (tester) async {
      final repo = FakeSourcesRepository(['/media/A', '/media/B']);
      await _open(tester, repo);
      expect(repo.order, ['/media/A', '/media/B']);

      await _dragRow(tester, 0, 1);

      expect(
        repo.order,
        ['/media/B', '/media/A'],
        reason:
            'the drag must reach reorderFolders — that write is what '
            'sortOrder, and therefore which copy plays, comes from',
      );
      // And the panel reflects it, so the preferred marker is not stale.
      expect(
        tester.getTopLeft(find.text('/media/B')).dy,
        lessThan(tester.getTopLeft(find.text('/media/A')).dy),
      );
    },
  );

  testWidgets('removing a source still goes through the repository', (
    tester,
  ) async {
    final repo = FakeSourcesRepository(['/media/A', '/media/B']);
    await _open(tester, repo);

    await tester.tap(find.byTooltip('Remove (drops its cached files)').first);
    await tester.pumpAndSettle();

    expect(repo.order, ['/media/B']);
    expect(find.text('/media/A'), findsNothing);
  });

  testWidgets('adding a source goes through the injected picker', (
    tester,
  ) async {
    final repo = FakeSourcesRepository(['/media/A']);
    var asked = false;
    await _open(
      tester,
      repo,
      // In production the picker writes the folder itself and the panel then
      // re-reads; here it is enough that the panel calls the INJECTED picker
      // rather than reaching for one of its own.
      onAddFolder: () async {
        asked = true;
        return (added: true, deniedLabel: null);
      },
    );

    await tester.tap(find.byTooltip('Add source'));
    await tester.pumpAndSettle();
    expect(asked, isTrue);
  });

  testWidgets(
    'closing reports a reorder so the screen underneath can re-read',
    (tester) async {
      final repo = FakeSourcesRepository(['/media/A', '/media/B']);
      final closed = await _open(tester, repo);
      await _dragRow(tester, 0, 1);

      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      expect(closed.outcome!.sourceOrderChanged, isTrue);
      expect(
        closed.outcome!.sourceSetChanged,
        isFalse,
        reason: 'a pure reorder needs a re-read, NOT a rescan',
      );
    },
  );

  testWidgets('an untouched window reports nothing changed', (tester) async {
    final repo = FakeSourcesRepository(['/media/A', '/media/B']);
    final closed = await _open(tester, repo);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(closed.outcome!.sourcesChanged, isFalse);
  });
}
