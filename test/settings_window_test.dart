import 'package:anilocal/domain/models/cache_footprint.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/show_preferences.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/source_descriptor.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/ui/settings/setting_row.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/settings_window.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/theme/xp_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_library_repository.dart';
import 'support/fake_sources.dart';
import 'support/finders.dart';
import 'support/recorder_settings.dart';

/// The Settings window is a two-pane sidebar shell of SEVEN tabs, each the
/// answer to one question: Folders · Sources · Playback · Display · Unmatched ·
/// Maintenance · About. These lock what a re-sort must not lose: every setting
/// still present, still reachable, and still writing through the same
/// repository — and the tab each row lives on, since putting a row back where
/// it used to be is exactly the drift the seven-tab layout replaced.
///
/// They also pin the two rules the shell exists to enforce — no long copy on
/// the always-visible surface, and no "Show / hide" labels — because those are
/// the things a later edit would quietly undo.

const _unmatchedFile = IdentifiedEpisode(
  filePath: '/lib/Mystery - 01.mkv',
  parsedTitle: 'Mystery',
  parsedEpisodeNumber: 1,
);

/// The sidebar, top to bottom. The Unmatched label carries the fake's count.
const _sidebar = [
  'Folders',
  'Sources',
  'Playback',
  'Display',
  'Unmatched (3)',
  'Maintenance',
  'About',
];

SettingsDialogActions _actions({
  Future<void> Function(IdentifiedEpisode)? onFixMatch,
  FakeSourcesRepository? sources,
  ValueListenable<int>? unmatchedCount,
  ValueListenable<bool>? scanning,
  ShowPreferencesRepository? showPreferences,
  MaintenanceActions maintenance = const MaintenanceActions.absent(),
}) =>
    SettingsActions(
      showPreferences: showPreferences ?? FakeLibraryRepository(),
      maintenance: maintenance,
      sources: fakeSourcesActions(sources ?? FakeSourcesRepository()),
      metadataSources: const [
        SourceDescriptor(token: 'anilist', displayName: 'AniList'),
        SourceDescriptor(token: 'kitsu', displayName: 'Kitsu'),
      ],
      skipSources: const [
        SourceDescriptor(
          token: 'chapters',
          displayName: 'Chapters in the file',
        ),
        SourceDescriptor(token: 'aniskip', displayName: 'AniSkip'),
      ],
      onRefreshMetadata: () async =>
          const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
      scanning: scanning ?? ValueNotifier<bool>(false),
    ).forScreen(
      onRefreshed: () {},
      unmatchedCount: unmatchedCount ?? ValueNotifier<int>(3),
      loadUnmatched: () async => const [_unmatchedFile],
      onFixMatch: onFixMatch ?? (_) async {},
    );

Future<RecorderSettings> _openSettings(
  WidgetTester tester, {
  SettingsDialogActions? actions,
  String? initialCategory,
}) async {
  tester.view.physicalSize = const Size(1200, 820);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = RecorderSettings();
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
              initialCategory: initialCategory,
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

/// Playback holds TWO text fields (m:ss and seconds), so a field is always
/// found through its row.
Finder _fieldIn(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SettingRow)),
  matching: find.byType(TextField),
);

/// The action button of a named row.
Finder _buttonIn(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SettingRow)),
  matching: find.byType(XpButton),
);

Future<void> _openCategory(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('settings window', () {
    testWidgets('the sidebar lists the seven categories in order', (
      tester,
    ) async {
      await _openSettings(tester);
      var lastY = double.negativeInfinity;
      for (final label in _sidebar) {
        final y = tester.getTopLeft(find.text(label)).dy;
        expect(y, greaterThan(lastY), reason: '$label is out of order');
        lastY = y;
      }
      // The tabs the re-sort folded away must not come back as entries.
      for (final gone in ['Library', 'Homepage', 'Metadata', 'Skip']) {
        expect(find.text(gone), findsNothing, reason: '$gone is a dead tab');
      }
    });

    testWidgets('every setting is present, on the tab its question lives on', (
      tester,
    ) async {
      await _openSettings(tester);

      // Folders is the landing panel (it leads the sidebar); this fake has no
      // folders, so it shows its empty state.
      expect(findXpLabel('Add a folder'), findsOneWidget);

      // Sources: BOTH provider lists on one page, each with its own top row.
      await _openCategory(tester, 'Sources');
      expect(findXpLabel('Show information'), findsOneWidget);
      expect(findXpLabel('Intro / outro timings'), findsOneWidget);
      for (final name in [
        'AniList',
        'Kitsu',
        'Chapters in the file',
        'AniSkip',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Source of truth'), findsNWidgets(2));

      // Playback: everything about skipping together, plus autoplay and the
      // watched threshold.
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
      expect(find.text('Ignore skips shorter than'), findsOneWidget);
      expect(find.text('Cross-check sources'), findsOneWidget);
      expect(find.text('Mark as watched'), findsOneWidget);

      // Display: what the homepage and the show pages show.
      await _openCategory(tester, 'Display');
      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.text('Search bar'), findsOneWidget);
      expect(find.text('Next episode'), findsOneWidget);
      expect(find.text('Missing episode placeholders'), findsOneWidget);
      expect(find.text('Airing status'), findsOneWidget);

      await _openCategory(tester, 'Maintenance');
      expect(find.text('Refresh metadata'), findsOneWidget);

      // The two rows that only jumped to another tab are gone for good.
      for (final category in ['Display', 'Maintenance']) {
        await _openCategory(tester, category);
        expect(find.text('Edit sources'), findsNothing);
        expect(find.text('Unmatched files'), findsNothing);
      }
    });

    testWidgets('the sidebar swaps panels — one category is shown at a time', (
      tester,
    ) async {
      await _openSettings(tester);
      await _openCategory(tester, 'Playback');
      expect(find.text('Autoplay next episode'), findsOneWidget);
      expect(find.text('Search bar'), findsNothing);

      await _openCategory(tester, 'Display');
      expect(find.text('Search bar'), findsOneWidget);
      expect(
        find.text('Autoplay next episode'),
        findsNothing,
        reason: 'the previous panel must be gone, not merely scrolled away',
      );
    });

    testWidgets(
      'a remembered category that no longer exists lands on Folders',
      (tester) async {
        await _openSettings(tester, initialCategory: 'library');
        expect(findXpLabel('Add a folder'), findsOneWidget);
        expect(findXpLabel('Done'), findsOneWidget, reason: 'window open');
      },
    );

    testWidgets('toggling writes through the repository, unchanged', (
      tester,
    ) async {
      final settings = await _openSettings(tester);
      await _openCategory(tester, 'Playback');

      await tester.tap(_switchIn('Autoplay next episode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto skip'));
      await tester.pumpAndSettle();

      await _openCategory(tester, 'Display');
      await tester.tap(_switchIn('Missing episode placeholders'));
      await tester.pumpAndSettle();
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

    testWidgets('the m:ss field still gates what gets persisted', (
      tester,
    ) async {
      final settings = await _openSettings(tester);
      await _openCategory(tester, 'Playback');
      final field = _fieldIn('Mark as watched');

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
        await _openCategory(tester, 'Display');

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
        expect(
          findXpLabel('Apply to all'),
          findsNothing,
          reason: 'no show carries its own choice, so nothing to ask about',
        );
      },
    );

    testWidgets('Next episode asks before overwriting a show\'s own choice', (
      tester,
    ) async {
      // One show shows the button on purpose; the master switch is about to
      // hide it everywhere.
      final prefs = FakeLibraryRepository(
        preferences: {7: const ShowPreferences(nextEpisodeHidden: false)},
      );
      final settings = await _openSettings(
        tester,
        actions: _actions(showPreferences: prefs),
      );
      await _openCategory(tester, 'Display');

      await tester.tap(_switchIn('Next episode'));
      await tester.pumpAndSettle();
      expect(findXpLabel('Apply to every show?'), findsOneWidget);
      expect(settings.writes, isEmpty, reason: 'nothing until answered');

      await tester.tap(findXpLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(settings.writes, isEmpty);
      expect(
        tester.widget<Switch>(_switchIn('Next episode')).value,
        isTrue,
        reason: 'the switch stays where it was',
      );

      await tester.tap(_switchIn('Next episode'));
      await tester.pumpAndSettle();
      await tester.tap(findXpLabel('Apply to all'));
      await tester.pumpAndSettle();
      expect(settings.writes, ['hideNext=true']);
    });

    testWidgets('long explanations live in the ⓘ popover, not on the surface', (
      tester,
    ) async {
      await _openSettings(tester);
      await _openCategory(tester, 'Playback');
      const detail = '0:00 turns off automatic watched-marking entirely.';
      const skipDetail = 'about 90 seconds';

      expect(
        find.textContaining(detail),
        findsNothing,
        reason: 'the always-visible surface must stay scannable',
      );
      expect(
        find.textContaining(skipDetail),
        findsNothing,
        reason: 'the seconds row used to carry a three-sentence subtitle',
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

    testWidgets('no row is labelled with "show / hide" phrasing', (
      tester,
    ) async {
      await _openSettings(tester);
      for (final category in ['Playback', 'Display', 'Maintenance', 'About']) {
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

    testWidgets('Reset settings asks, then resets and says so', (tester) async {
      final settings = await _openSettings(tester);
      await _openCategory(tester, 'Maintenance');

      await tester.tap(_buttonIn('Reset settings'));
      await tester.pumpAndSettle();
      expect(findXpLabel('Reset all settings?'), findsOneWidget);
      await tester.tap(findXpLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(settings.writes, isEmpty, reason: 'cancel resets nothing');

      await tester.tap(_buttonIn('Reset settings'));
      await tester.pumpAndSettle();
      await tester.tap(findXpLabel('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(settings.writes, ['reset']);
      expect(find.text('Settings reset.'), findsOneWidget);
      expect(findXpLabel('Done'), findsOneWidget, reason: 'window stays open');
    });

    testWidgets('Maintenance names and measures the data folder', (
      tester,
    ) async {
      await _openSettings(
        tester,
        actions: _actions(
          maintenance: MaintenanceActions(
            dataPath: '/x/anilocal',
            measureFootprint: () async => const CacheFootprint(
              databaseBytes: 1000,
              artBytes: 2000,
              logsBytes: 0,
              otherBytes: 0,
            ),
            resetCache: () async => '/x/cache.sqlite.broken-1',
            scanning: ValueNotifier<bool>(false),
          ),
        ),
      );
      await _openCategory(tester, 'Maintenance');
      expect(find.text('/x/anilocal'), findsOneWidget);
      expect(find.textContaining('3.00 kB — database 1.00 kB'), findsOneWidget);
    });

    testWidgets('without a folder behind it, Maintenance says so', (
      tester,
    ) async {
      await _openSettings(tester);
      await _openCategory(tester, 'Maintenance');
      expect(find.text('Not available'), findsNWidgets(2));
      expect(
        tester.widget<XpButton>(_buttonIn('Data folder')).onPressed,
        isNull,
      );
      expect(
        tester.widget<XpButton>(_buttonIn('Reset library cache')).onPressed,
        isNull,
      );
    });

    testWidgets(
      'Reset library cache asks, resets, then holds at a quit prompt',
      (tester) async {
        var resets = 0;
        final scanning = ValueNotifier<bool>(true);
        await _openSettings(
          tester,
          actions: _actions(
            maintenance: MaintenanceActions(
              dataPath: '/x/anilocal',
              measureFootprint: null,
              resetCache: () async {
                resets++;
                return '/x/cache.sqlite.broken-1';
              },
              scanning: scanning,
            ),
          ),
        );
        await _openCategory(tester, 'Maintenance');

        // Refused while a scan runs: the scan writes the database the reset
        // closes.
        expect(
          tester.widget<XpButton>(_buttonIn('Reset library cache')).onPressed,
          isNull,
        );
        scanning.value = false;
        await tester.pumpAndSettle();

        await tester.tap(_buttonIn('Reset library cache'));
        await tester.pumpAndSettle();
        expect(findXpLabel('Reset library cache?'), findsOneWidget);
        await tester.tap(findXpLabel('Cancel'));
        await tester.pumpAndSettle();
        expect(resets, 0, reason: 'nothing until confirmed');

        await tester.tap(_buttonIn('Reset library cache'));
        await tester.pumpAndSettle();
        await tester.tap(findXpLabel('Reset and quit'));
        await tester.pumpAndSettle();
        expect(resets, 1);
        expect(
          find.textContaining('/x/cache.sqlite.broken-1'),
          findsOneWidget,
          reason: 'the prompt names where the old cache went',
        );
        expect(findXpLabel('Quit AniLocal'), findsOneWidget);
        // The prompt cannot be dismissed: the database behind the window is
        // closed, so the only way on is out.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(findXpLabel('Quit AniLocal'), findsOneWidget);
      },
    );

    testWidgets('Unmatched is a category whose label carries the live count', (
      tester,
    ) async {
      final count = ValueNotifier<int>(3);
      await _openSettings(tester, actions: _actions(unmatchedCount: count));
      expect(find.text('Unmatched (3)'), findsOneWidget);
      count.value = 0;
      await tester.pumpAndSettle();
      expect(find.text('Unmatched'), findsOneWidget);
      expect(find.text('Unmatched (3)'), findsNothing);
    });

    testWidgets('Fix match closes the window, then hands the file over', (
      tester,
    ) async {
      IdentifiedEpisode? fixed;
      await _openSettings(
        tester,
        actions: _actions(onFixMatch: (f) async => fixed = f),
      );
      await _openCategory(tester, 'Unmatched (3)');
      await tester.tap(find.text('Mystery - 01.mkv'));
      await tester.pumpAndSettle();
      expect(fixed, _unmatchedFile);
      expect(findXpLabel('Done'), findsNothing, reason: 'window dismissed');
    });

    testWidgets('Escape closes the window', (tester) async {
      await _openSettings(tester);
      expect(findXpLabel('Done'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(findXpLabel('Done'), findsNothing);
    });

    testWidgets('a click outside closes the window', (tester) async {
      await _openSettings(tester);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(findXpLabel('Done'), findsNothing);
    });

    testWidgets('closing under a focused seconds field still commits it', (
      tester,
    ) async {
      final settings = await _openSettings(tester);
      await _openCategory(tester, 'Playback');
      await tester.enterText(_fieldIn('Ignore skips shorter than'), '45');
      // Escape with the field focused: the route pops with no blur cycle.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(settings.writes, contains('minSkip=45'));

      final again = await _openSettings(tester);
      await _openCategory(tester, 'Playback');
      await tester.enterText(_fieldIn('Ignore skips shorter than'), '50');
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(again.writes, contains('minSkip=50'));
    });
  });
}
