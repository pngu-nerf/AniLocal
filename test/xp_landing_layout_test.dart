import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';

/// A library with several shows + a couple of in-progress entries, so a pump
/// exercises every XP zone at once: toolbar, search, the continue-watching side
/// panel, and the grid.
const _series = [
  Series(
    seriesId: 1,
    titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
    format: 'TV',
    episodeCount: 28,
  ),
  Series(
    seriesId: 2,
    titles: Titles(romaji: 'Bocchi the Rock!', english: 'Bocchi the Rock!'),
    format: 'TV',
    episodeCount: 12,
  ),
  Series(
    seriesId: 3,
    titles: Titles(romaji: 'Cowboy Bebop', english: 'Cowboy Bebop'),
    format: 'TV',
    episodeCount: 26,
  ),
  Series(
    seriesId: -7,
    titles: Titles(romaji: '[SubsPlease] Dandadan - 03'),
    pending: true,
  ),
];

const _episode = Episode(
  number: 5,
  fileRef: '/x/ep5.mkv',
  seriesId: 1,
  anchoredNumber: 5,
  resumePosition: Duration(minutes: 8),
  duration: Duration(minutes: 24),
);

Widget _app() {
  final repo = FakeLibraryRepository(
    series: _series,
    continuing: [ContinueWatching(series: _series[0], episode: _episode)],
  );
  return AniLocalApp(
    repository: repo,
    fixMatch: const FakeFixMatch(),
    watchState: repo,
    sourceSelection: repo,
    missing: repo,
    showPreferences: repo,
    settings: const FakeSettings(),
    watchOrder: repo,
    playback: PlaybackController(resolver: repo),
    onScan: (_, {onProgress, cancellation}) async => const SyncSummary(
      filesScanned: 0,
      unchanged: 0,
      processed: 0,
      removed: 0,
      matched: 0,
      unmatched: 0,
      errored: 0,
      lookupsBySource: {},
    ),
    onRefreshMetadata: () async =>
        const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
    onAddFolder: () async => (added: false, deniedLabel: null),
    accessIssues: ValueNotifier<List<String>>(const []),
    missingFolders: ValueNotifier<List<String>>(const []),
    missingFolderPaths: ValueNotifier<Set<String>>(const {}),
    categoryLabelOf: (_) => null,
    onOpenAccessSettings: () async => true,
  );
}

void main() {
  group('XP landing layout', () {
    // A RenderFlex/RenderBox overflow logs a FlutterError during layout, which
    // fails the test — so a clean pump at each width proves the chunky XP chrome
    // (window frame, toolbar, search, side panel, grid) fits without overflow.
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app());
      // Bounded pumps (not pumpAndSettle): the header VFD readout can run a
      // continuous marquee for a long/cramped title, which never "settles". Two
      // pumps resolve the in-memory repo futures and render the grid.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('XP landing fits at a normal window width', (tester) async {
      await pumpAt(tester, const Size(1100, 760));
      expect(find.byType(HeaderReadout), findsOneWidget); // title bar
      expect(find.text('Bocchi the Rock!'), findsOneWidget); // grid card
      expect(
        find.bySemanticsLabel('Continue watching'),
        findsOneWidget,
      ); // side panel
      expect(find.text('Search your library'), findsOneWidget); // search hint
      // Frieren shows in BOTH the grid and the continue-watching panel.
      expect(find.text('Frieren'), findsNWidgets(2));
    });

    testWidgets('XP landing fits at a narrow window width', (tester) async {
      await pumpAt(tester, const Size(380, 720));
      // Still renders the chrome + content with no overflow at a cramped width.
      expect(find.byType(HeaderReadout), findsOneWidget);
      expect(find.text('Bocchi the Rock!'), findsOneWidget);
      expect(find.bySemanticsLabel('Continue watching'), findsOneWidget);
    });

    testWidgets('XP landing fits at the minimum window size (600x400)', (
      tester,
    ) async {
      // The native window can't be resized below 600x400 logical points
      // (MainFlutterWindow.contentMinSize). A clean pump here (no RenderFlex
      // overflow) proves the home screen — title bar with labelled tabs, search,
      // continue-watching sidebar, grid — stays usable at that minimum. It's the
      // tightest size the app can actually reach.
      await pumpAt(tester, const Size(600, 400));
      expect(find.byType(HeaderReadout), findsOneWidget);
      expect(find.bySemanticsLabel('Continue watching'), findsOneWidget);
      expect(find.text('Search your library'), findsOneWidget);
      // A grid card still renders (grid remains present beside the sidebar).
      expect(find.text('Bocchi the Rock!'), findsOneWidget);
    });

    testWidgets('search filters the grid live and clearing restores it', (
      tester,
    ) async {
      await pumpAt(tester, const Size(1100, 760));
      await tester.enterText(find.byType(TextField), 'bocchi');
      await tester.pumpAndSettle();
      expect(find.text('Bocchi the Rock!'), findsOneWidget);
      // Cowboy Bebop is grid-only, so the filter removes it entirely.
      expect(find.text('Cowboy Bebop'), findsNothing);

      // Clearing the query (the X button) restores the full library.
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Cowboy Bebop'), findsOneWidget);
      expect(find.text('Bocchi the Rock!'), findsOneWidget);
    });
  });
}
