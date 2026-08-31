import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/ui/settings/setting_row.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/settings_window.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_settings.dart';
import 'support/fake_sources.dart';

/// The Settings window was rebuilt from one scrolling list of collapsibles into
/// a two-pane sidebar shell. That was a STRUCTURAL and PRESENTATIONAL change
/// only, so these lock the part that must not have moved: every setting still
/// present, still reachable, and still writing through the same repository.
///
/// They also pin the two rules the rebuild exists to enforce — no long copy on
/// the always-visible surface, and no "Show / hide" labels — because those are
/// the things a later edit would quietly undo.

/// Records writes so a test can assert what reached the repository, and only
/// that. Reads come from [FakeSettings]' production defaults.
class _Recorder extends FakeSettings {
  final List<String> writes = [];

  @override
  Future<void> setAutoPlayNext(bool enabled) async =>
      writes.add('autoPlayNext=$enabled');
  @override
  Future<void> setSkipMode(SkipMode mode) async =>
      writes.add('skip=${mode.name}');
  @override
  Future<void> setMissingEnabled(bool enabled) async =>
      writes.add('missing=$enabled');
  @override
  Future<void> setHideNextEpisode(bool hidden) async =>
      writes.add('hideNext=$hidden');
  @override
  Future<void> setShowContinueWatching(bool show) async =>
      writes.add('continue=$show');
  @override
  Future<void> setShowSearchBar(bool show) async => writes.add('search=$show');
  @override
  Future<void> setWatchedThreshold(Duration v) async =>
      writes.add('threshold=${v.inSeconds}');
}

SettingsDialogActions _actions({
  VoidCallback? onUnmatched,
  FakeSourcesRepository? sources,
}) => SettingsDialogActions(
  sources: fakeSourcesActions(sources ?? FakeSourcesRepository()),
  onRefreshMetadata: () async => (seriesRefreshed: 0, skipsFetched: 0),
  onRefreshed: () {},
  loadUnmatchedCount: () async => 3,
  onOpenUnmatched: onUnmatched ?? () {},
);

Future<_Recorder> _openSettings(
  WidgetTester tester, {
  SettingsDialogActions? actions,
}) async {
  tester.view.physicalSize = const Size(1200, 820);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      theme: XpTheme.data(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAppSettingsDialog(
              context,
              settings: settings,
              actions: actions ?? _actions(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return settings;
}

/// The control belonging to a named row — resolved through the row, never by
/// position, so reordering a panel can't silently repoint a test.
Finder _switchIn(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SettingRow)),
  matching: find.byType(Switch),
);

Future<void> _openCategory(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every migrated setting is present and reachable', (
    tester,
  ) async {
    await _openSettings(tester);

    // Sources is the landing panel (it leads the sidebar); this fake has no
    // folders, so it shows its empty state.
    expect(find.text('ADD A SOURCE'), findsOneWidget);

    await _openCategory(tester, 'Playback');
    expect(find.text('Autoplay next episode'), findsOneWidget);
    expect(find.text('Skip intro / outro'), findsOneWidget);
    for (final mode in SkipMode.values) {
      expect(
        find.text(switch (mode) {
          SkipMode.off => 'No skip',
          SkipMode.button => 'Skip button',
          SkipMode.auto => 'Auto skip',
        }),
        findsOneWidget,
      );
    }
    expect(find.text('Mark as watched'), findsOneWidget);

    await _openCategory(tester, 'Library');
    expect(find.text('Missing episode placeholders'), findsOneWidget);
    expect(find.text('Refresh metadata'), findsOneWidget);
    expect(find.text('Edit sources'), findsOneWidget);
    // Moved down from the old top level into library health.
    expect(find.text('Unmatched files'), findsOneWidget);
    expect(find.text('3 file(s) we could not identify'), findsOneWidget);

    await _openCategory(tester, 'Homepage');
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Search bar'), findsOneWidget);
    expect(find.text('Next episode'), findsOneWidget);
  });

  testWidgets('the sidebar swaps panels — one category is shown at a time', (
    tester,
  ) async {
    await _openSettings(tester);
    await _openCategory(tester, 'Playback');
    expect(find.text('Autoplay next episode'), findsOneWidget);
    expect(find.text('Search bar'), findsNothing);

    await _openCategory(tester, 'Homepage');
    expect(find.text('Search bar'), findsOneWidget);
    expect(
      find.text('Autoplay next episode'),
      findsNothing,
      reason: 'the previous panel must be gone, not merely scrolled away',
    );
  });

  testWidgets('toggling writes through the repository, unchanged', (
    tester,
  ) async {
    final settings = await _openSettings(tester);
    await _openCategory(tester, 'Playback');

    await tester.tap(_switchIn('Autoplay next episode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto skip'));
    await tester.pumpAndSettle();

    await _openCategory(tester, 'Library');
    await tester.tap(_switchIn('Missing episode placeholders'));
    await tester.pumpAndSettle();

    await _openCategory(tester, 'Homepage');
    await tester.tap(_switchIn('Continue watching'));
    await tester.pumpAndSettle();
    await tester.tap(_switchIn('Search bar'));
    await tester.pumpAndSettle();

    expect(settings.writes, [
      'autoPlayNext=false',
      'skip=auto',
      'missing=false',
      'continue=false',
      'search=false',
    ]);
  });

  testWidgets('the m:ss field still gates what gets persisted', (tester) async {
    final settings = await _openSettings(tester);
    await _openCategory(tester, 'Playback');
    final field = find.byType(TextField);

    await tester.enterText(field, '2:15');
    await tester.pumpAndSettle();
    await tester.enterText(field, '9:99'); // invalid — must not be written
    await tester.pumpAndSettle();

    expect(settings.writes, ['threshold=135']);
    expect(find.text('m:ss, max 9:59'), findsOneWidget);
  });

  testWidgets(
    'Next episode reads positively but persists the hide flag unchanged',
    (tester) async {
      final settings = await _openSettings(tester);
      await _openCategory(tester, 'Homepage');

      // Stored hideNextEpisode is false, so the positive row shows ON.
      expect(tester.widget<Switch>(_switchIn('Next episode')).value, isTrue);

      await tester.tap(_switchIn('Next episode'));
      await tester.pumpAndSettle();
      expect(
        settings.writes,
        ['hideNext=true'],
        reason:
            'only the DISPLAY polarity was inverted; the persisted '
            'hide-semantics must be untouched',
      );
    },
  );

  testWidgets('long explanations live in the ⓘ popover, not on the surface', (
    tester,
  ) async {
    await _openSettings(tester);
    await _openCategory(tester, 'Playback');
    const detail = '0:00 turns off automatic watched-marking entirely.';

    expect(
      find.textContaining(detail),
      findsNothing,
      reason: 'the always-visible surface must stay scannable',
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Mark as watched'),
          matching: find.byType(SettingRow),
        ),
        matching: find.byType(SettingInfo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(detail), findsOneWidget);
  });

  testWidgets('no row is labelled with "show / hide" phrasing', (tester) async {
    await _openSettings(tester);
    for (final category in ['Playback', 'Library', 'Homepage']) {
      await _openCategory(tester, category);
      for (final row in tester.widgetList<SettingRow>(
        find.byType(SettingRow),
      )) {
        final label = row.label.toLowerCase();
        expect(
          label.contains('show') || label.contains('hide'),
          isFalse,
          reason:
              '"${row.label}" ($category) states a visibility toggle as a '
              'show/hide instruction instead of naming the thing',
        );
      }
    }
  });

  testWidgets('a navigation row closes the window before navigating', (
    tester,
  ) async {
    var opened = false;
    await _openSettings(
      tester,
      actions: _actions(onUnmatched: () => opened = true),
    );
    await _openCategory(tester, 'Library');

    await tester.tap(find.text('Unmatched files'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(find.byType(SettingRow), findsNothing, reason: 'window dismissed');
  });
}
