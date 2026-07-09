import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakeRepository
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository {
  @override
  Future<List<Series>> allSeries() async => const [
    Series(
      anilistId: 154587,
      titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
      format: 'TV',
      episodeCount: 28,
    ),
  ];

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
  Future<void> clearProgress(Episode episode) async {}

  @override
  Future<List<ContinueWatching>> continueWatching() async => const [];

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
}

void main() {
  testWidgets('library renders cached series from the repository', (
    tester,
  ) async {
    await tester.pumpWidget(
      AniLocalApp(
        repository: _FakeRepository(),
        fixMatch: _FakeFixMatch(),
        watchState: _FakeRepository(),
        sourceSelection: _FakeRepository(),
        watchOrder: _FakeRepository(),
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
        loadContinueCollapsed: () async => false,
        setContinueCollapsed: (_) async {},
        loadAutoPlayNext: () async => true,
        setAutoPlayNext: (_) async {},
        loadSkipMode: () async => SkipMode.button,
        setSkipMode: (_) async {},
        loadRailFraction: () async => 0.30,
        setRailFraction: (_) async {},
        loadPanelFraction: () async => 0.22,
        setPanelFraction: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('AniLocal'), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.textContaining('TV'), findsOneWidget);
  });
}
