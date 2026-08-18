import 'dart:async';

import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/show_preferences.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/missing_episodes_repository.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/series_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_settings.dart';
import 'support/shell_harness.dart';

/// The detail page's FIRST FRAME.
///
/// The route is handed a complete [Series] — title, cover, meta — so none of
/// that should wait on the database. Only the episode list has to. These pin
/// that the hero paints while the episode query is still outstanding, and that
/// the page asks the data layer for as little as it can.

Series _series() => const Series(
  anilistId: 7,
  titles: Titles(romaji: 'Dragon Ball', native: 'ドラゴンボール'),
);

/// Episodes 1–3, with 1 and 2 watched — so "next" is unambiguously episode 3.
List<Episode> _episodes() => [
  for (var i = 1; i <= 3; i++)
    Episode(
      number: i,
      fileRef: '/tmp/ep$i.mkv',
      seriesAnilistId: 7,
      anchoredNumber: i,
      watched: i <= 2,
    ),
];

class _Repo
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository,
        MissingEpisodesRepository,
        ShowPreferencesRepository {
  _Repo({this.episodesCompleter, List<Episode>? episodes})
    : _episodesOverride = episodes;

  final List<Episode>? _episodesOverride;

  /// When supplied, `episodesFor` hangs until the test completes it — that is
  /// how "the DB hasn't answered yet" is simulated.
  final Completer<List<Episode>>? episodesCompleter;

  /// Every call the page makes, so a test can assert on what it DIDN'T ask for.
  final List<String> calls = [];

  @override
  Future<List<Episode>> episodesFor(int anilistId) {
    calls.add('episodesFor');
    return episodesCompleter?.future ??
        Future.value(_episodesOverride ?? _episodes());
  }

  @override
  Future<Map<int, Episode>> upNextBySeries() async {
    calls.add('upNextBySeries');
    return {7: _episodes()[2]};
  }

  @override
  Future<Set<int>> hiddenEpisodes(int anilistId) async {
    calls.add('hiddenEpisodes');
    return const {};
  }

  @override
  Future<List<Series>> allSeries() async => [_series()];
  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async => const [];
  @override
  Future<List<LibraryFolder>> watchedFolders() async => const [];
  @override
  Future<void> addFolder(String path) async {}
  @override
  Future<void> removeFolder(LibraryFolder folder) async {}
  @override
  Future<void> reorderFolders(List<LibraryFolder> ordered) async {}
  @override
  Future<void> saveProgress(
    Episode e, {
    required Duration position,
    required Duration duration,
  }) async {}
  @override
  Future<void> setWatched(Episode e, {required bool watched}) async {}
  @override
  Future<void> setWatchedManual(Episode e, {required bool watched}) async {}
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
  Future<Map<int, Set<int>>> allHiddenEpisodes() async => const {};
  @override
  Future<void> hideEpisodes(int id, List<int> eps) async {}
  @override
  Future<void> unhideEpisodes(int id, List<int> eps) async {}
  @override
  Future<ShowPreferences> preferencesFor(int id) async =>
      const ShowPreferences();
  @override
  Future<Map<int, ShowPreferences>> allPreferences() async => const {};
  @override
  Future<void> setPictureMode(int id, PictureMode m) async {}
  @override
  Future<void> setNextEpisodeHidden(int id, {required bool hidden}) async {}
  @override
  Future<void> setAllNextEpisodeHidden({required bool hidden}) async {}
}

class _FixMatch implements FixMatchRepository {
  @override
  Future<List<Series>> searchCandidates(String q) async => const [];
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

Widget _app(_Repo repo) {
  final h = ShellHarness();
  return h.app(
    home: SeriesDetailScreen(
      series: _series(),
      repository: repo,
      fixMatch: _FixMatch(),
      watchState: repo,
      sourceSelection: repo,
      watchOrder: repo,
      playback: PlaybackController(resolver: repo),
      missing: repo,
      settings: const FakeSettings(),
      onRefreshMetadata: () async => (seriesRefreshed: 0, skipsFetched: 0),
      onFolders: () async {},
      onScan: () async {},
      onUnmatched: () {},
      unmatchedCount: 0,
    ),
  );
}

void main() {
  testWidgets('the hero paints on the FIRST frame, while the episode query is '
      'still outstanding', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // episodesFor never completes during this test: the DB is "still thinking".
    final pending = Completer<List<Episode>>();
    addTearDown(() => pending.complete(const []));
    await tester.pumpWidget(_app(_Repo(episodesCompleter: pending)));
    await tester.pump();

    expect(
      find.text('Dragon Ball'),
      findsWidgets,
      reason:
          'the title comes from the Series the route was handed — it must '
          'not wait on the database',
    );
    expect(find.text('ドラゴンボール'), findsWidgets);
    // …and the episode list is honestly still loading.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('the page does NOT rebuild the whole library to find its own '
      'next episode', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _Repo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      isNot(contains('upNextBySeries')),
      reason:
          'upNextBySeries rebuilds every series logical-episode map to read '
          'one entry; next-episode is derivable from the list already loaded',
    );
  });

  testWidgets('the derived next episode matches what upNextBySeries would have '
      'returned', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _Repo();
    // The old query's answer for this series, computed by the real repository
    // semantics: furthest watched is 2, so next is the episode at anchor 3.
    final expected = (await repo.upNextBySeries())[7]!;
    repo.calls.clear();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(SeriesDetailScreen));
    final derived = (state as dynamic).debugNextEpisode as Episode?;
    expect(derived, isNotNull);
    expect(derived!.anchoredNumber, expected.anchoredNumber);
    expect(derived.number, expected.number);
    expect(derived.watched, isFalse);
  });

  group('the derivation matches upNextBySeries across its branches', () {
    // upNextBySeries: furthest WATCHED anchor -> the episode at anchor+1, shown
    // only if it exists and is unwatched. These drive each branch of that rule
    // through the real screen.
    Future<Episode?> derived(WidgetTester tester, List<Episode> eps) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(_Repo(episodes: eps)));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(SeriesDetailScreen));
      return (state as dynamic).debugNextEpisode as Episode?;
    }

    Episode ep(int n, {bool watched = false}) => Episode(
      number: n,
      fileRef: '/tmp/ep$n.mkv',
      seriesAnilistId: 7,
      anchoredNumber: n,
      watched: watched,
    );

    testWidgets('nothing watched -> no next (a series never started)', (
      tester,
    ) async {
      expect(await derived(tester, [ep(1), ep(2), ep(3)]), isNull);
    });

    testWidgets('caught up -> no next', (tester) async {
      final all = [ep(1, watched: true), ep(2, watched: true)];
      expect(await derived(tester, all), isNull);
    });

    testWidgets('resolves from the FURTHEST watched, not the first gap', (
      tester,
    ) async {
      // Watched 1 and 3 (2 skipped): furthest is 3, so next is 4 — NOT 2.
      final eps = [ep(1, watched: true), ep(2), ep(3, watched: true), ep(4)];
      final next = await derived(tester, eps);
      expect(next?.anchoredNumber, 4);
    });

    testWidgets('no episode after the furthest watched -> no next', (
      tester,
    ) async {
      expect(await derived(tester, [ep(1), ep(2, watched: true)]), isNull);
    });
  });
}
