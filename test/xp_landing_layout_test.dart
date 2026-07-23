import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/missing_episodes_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_settings.dart';
import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/domain/models/show_preferences.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/ui/theme/header_readout.dart';

/// A library with several shows + a couple of in-progress entries, so a pump
/// exercises every XP zone at once: toolbar, search, the continue-watching side
/// panel, and the grid.
class _FakeRepository
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository,
        MissingEpisodesRepository,
        ShowPreferencesRepository {
  static const _series = [
    Series(
      anilistId: 1,
      titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
      format: 'TV',
      episodeCount: 28,
    ),
    Series(
      anilistId: 2,
      titles: Titles(romaji: 'Bocchi the Rock!', english: 'Bocchi the Rock!'),
      format: 'TV',
      episodeCount: 12,
    ),
    Series(
      anilistId: 3,
      titles: Titles(romaji: 'Cowboy Bebop', english: 'Cowboy Bebop'),
      format: 'TV',
      episodeCount: 26,
    ),
    Series(
      anilistId: -7,
      titles: Titles(romaji: '[SubsPlease] Dandadan - 03'),
      pending: true,
    ),
  ];

  static const _episode = Episode(
    number: 5,
    fileRef: '/x/ep5.mkv',
    seriesAnilistId: 1,
    anchoredNumber: 5,
    resumePosition: Duration(minutes: 8),
    duration: Duration(minutes: 24),
  );

  @override
  Future<List<Series>> allSeries() async => _series;

  @override
  Future<List<Episode>> episodesFor(int anilistId) async => const [];

  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async => const [];

  @override
  Future<List<LibraryFolder>> watchedFolders() async => const [];

  @override
  Future<void> addFolder(String path) async {}

  @override
  Future<void> removeFolder(LibraryFolder folder) async {}

  @override
  Future<void> reorderFolders(List<LibraryFolder> orderedFolders) async {}

  @override
  Future<void> saveProgress(
    Episode episode, {
    required Duration position,
    required Duration duration,
  }) async {}

  @override
  Future<void> setWatched(Episode episode, {required bool watched}) async {}

  @override
  Future<void> setWatchedManual(Episode e, {required bool watched}) async {}

  @override
  Future<ShowPreferences> preferencesFor(int anilistId) async =>
      const ShowPreferences();
  @override
  Future<Map<int, ShowPreferences>> allPreferences() async => const {};
  @override
  Future<void> setPictureMode(int anilistId, PictureMode mode) async {}
  @override
  Future<void> setNextEpisodeHidden(
    int anilistId, {
    required bool hidden,
  }) async {}

  @override
  Future<void> setAllNextEpisodeHidden({required bool hidden}) async {}

  @override
  Future<void> clearProgress(Episode episode) async {}

  @override
  Future<List<ContinueWatching>> continueWatching() async => [
    ContinueWatching(series: _series[0], episode: _episode),
  ];

  @override
  Future<void> selectSource(
    Episode episode, {
    required String folderPath,
  }) async {}

  @override
  Future<void> clearSource(Episode episode) async {}

  @override
  Future<NextResult> nextEpisode(Episode current) async =>
      const NoNextEpisode();

  @override
  Future<Map<int, Episode>> upNextBySeries() async => const {};
  @override
  Future<Set<int>> hiddenEpisodes(int anilistId) async => const {};
  @override
  Future<Map<int, Set<int>>> allHiddenEpisodes() async => const {};
  @override
  Future<void> hideEpisodes(int anilistId, List<int> episodes) async {}
  @override
  Future<void> unhideEpisodes(int anilistId, List<int> episodes) async {}
}

class _FakeFixMatch implements FixMatchRepository {
  @override
  Future<List<Series>> searchCandidates(String query) async => const [];
  @override
  Future<void> assignFile({
    required String filePath,
    required Series chosen,
    int? anchoredEpisode,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {}
  @override
  Future<void> assignRange({
    required List<String> filePaths,
    required Series chosen,
    int anchorStart = 1,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {}
  @override
  Future<void> clearOverride(String filePath) async {}
}

Widget _app() {
  final repo = _FakeRepository();
  return AniLocalApp(
    repository: repo,
    fixMatch: _FakeFixMatch(),
    watchState: repo,
    sourceSelection: repo,
    missing: repo,
    showPreferences: repo,
    settings: const FakeSettings(),
    watchOrder: repo,
    onScan: (_) async => const SyncSummary(
      filesScanned: 0,
      unchanged: 0,
      processed: 0,
      removed: 0,
      matched: 0,
      unmatched: 0,
      errored: 0,
      anilistLookups: 0,
    ),
    onRefreshMetadata: () async => (seriesRefreshed: 0, skipsFetched: 0),
    onAddFolder: () async => (added: false, deniedLabel: null),
    accessIssues: ValueNotifier<List<String>>(const []),
    missingFolders: ValueNotifier<List<String>>(const []),
    missingFolderPaths: ValueNotifier<Set<String>>(const {}),
    onOpenAccessSettings: () async => true,
  );
}

void main() {
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
}
