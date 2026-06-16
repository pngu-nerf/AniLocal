import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
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

const _emptySummary = SyncSummary(
  filesScanned: 0,
  unchanged: 0,
  processed: 0,
  removed: 0,
  matched: 0,
  unmatched: 0,
  errored: 0,
  anilistLookups: 0,
);

class _MutableRepo
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository {
  _MutableRepo(this.folders);
  List<String> folders;

  @override
  Future<List<LibraryFolder>> watchedFolders() async => [
    for (final p in folders) LibraryFolder(path: p),
  ];

  @override
  Future<List<Series>> allSeries() async => const [];
  @override
  Future<List<Episode>> episodesFor(int anilistId) async => const [];
  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async => const [];
  @override
  Future<void> addFolder(String path) async => folders = [...folders, path];
  @override
  Future<void> removeFolder(LibraryFolder folder) async =>
      folders = folders.where((p) => p != folder.path).toList();

  @override
  Future<void> reorderFolders(List<LibraryFolder> orderedFolders) async =>
      folders = [for (final f in orderedFolders) f.path];

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
  testWidgets('rescan fires only when the folder set actually changed', (
    tester,
  ) async {
    final repo = _MutableRepo(['/a']);
    var scans = 0;

    await tester.pumpWidget(
      AniLocalApp(
        repository: repo,
        fixMatch: _FakeFixMatch(),
        watchState: repo,
        sourceSelection: repo,
        watchOrder: repo,
        onScan: (_) async {
          scans++;
          return _emptySummary;
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
      ),
    );
    await tester.pumpAndSettle();

    // 1) Open the folders screen and close it WITHOUT changing the set.
    await tester.tap(find.byTooltip('Library folders'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scans, 0, reason: 'no-op dismissal must not scan');

    // 2) Open it, change the set (simulate an add), then close.
    await tester.tap(find.byTooltip('Library folders'));
    await tester.pumpAndSettle();
    repo.folders = ['/a', '/b'];
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scans, 1, reason: 'a changed folder set triggers one rescan');
  });
}
