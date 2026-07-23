import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/missing_episodes_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_settings.dart';
import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/domain/models/show_preferences.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/ui/theme/header_readout.dart';

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
        WatchOrderRepository,
        MissingEpisodesRepository,
        ShowPreferencesRepository {
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

  @override
  Future<Set<int>> hiddenEpisodes(int anilistId) async => const {};
  @override
  Future<Map<int, Set<int>>> allHiddenEpisodes() async => const {};
  @override
  Future<void> hideEpisodes(int anilistId, List<int> episodes) async {}
  @override
  Future<void> unhideEpisodes(int anilistId, List<int> episodes) async {}
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
        missing: _FakeRepository(),
        showPreferences: _FakeRepository(),
        settings: const FakeSettings(),
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
      ),
    );
    // Bounded pumps, not pumpAndSettle: the header VFD readout may run a
    // continuous marquee (which never settles). Two pumps resolve the futures
    // and render the grid.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HeaderReadout), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.textContaining('TV'), findsOneWidget);
  });
}
