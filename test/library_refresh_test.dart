import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _summary = SyncSummary(
  filesScanned: 1,
  unchanged: 0,
  processed: 1,
  removed: 0,
  matched: 1,
  unmatched: 0,
  errored: 0,
  anilistLookups: 0,
);

Series _s(int id, String title) => Series(
  anilistId: id,
  titles: Titles(romaji: title),
);

class _MutableLib
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository {
  List<Series> series = [];

  @override
  Future<List<Series>> allSeries() async => series;
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
    Episode e, {
    required Duration position,
    required Duration duration,
  }) async {}
  @override
  Future<void> setWatched(Episode e, {required bool watched}) async {}
  @override
  Future<void> clearProgress(Episode e) async {}
  @override
  Future<List<ContinueWatching>> continueWatching() async => const [];
  @override
  Future<void> selectSource(Episode e, {required String folderPath}) async {}
  @override
  Future<void> clearSource(Episode e) async {}
  @override
  Future<NextResult> nextEpisode(Episode current) async =>
      const NoNextEpisode();
  @override
  Future<Map<int, Episode>> upNextBySeries() async => const {};
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

void main() {
  testWidgets('library grid re-reads the cache after a scan completes', (
    tester,
  ) async {
    final repo = _MutableLib()..series = [_s(1, 'Alpha')];

    await tester.pumpWidget(
      AniLocalApp(
        repository: repo,
        fixMatch: _FakeFixMatch(),
        watchState: repo,
        sourceSelection: repo,
        watchOrder: repo,
        onScan: (_) async {
          // A scan that adds a new series to the cache.
          repo.series = [_s(1, 'Alpha'), _s(2, 'Bravo')];
          return _summary;
        },
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

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);

    await tester.tap(find.byTooltip('Sync metadata'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bravo'),
      findsOneWidget,
      reason: 'grid must reflect the post-scan cache',
    );
    expect(find.text('Alpha'), findsOneWidget);
  });
}
