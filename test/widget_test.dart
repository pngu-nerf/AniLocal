import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements LibraryRepository {
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
}

void main() {
  testWidgets('library renders cached series from the repository', (
    tester,
  ) async {
    await tester.pumpWidget(
      AniLocalApp(
        repository: _FakeRepository(),
        onScan: () async => const SyncSummary(
          filesScanned: 0,
          unchanged: 0,
          processed: 0,
          removed: 0,
          matched: 0,
          unmatched: 0,
          errored: 0,
          anilistLookups: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AniLocal'), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.textContaining('TV'), findsOneWidget);
  });
}
