import 'dart:async';

import 'package:anilocal/domain/models/continue_watching.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/library_snapshot.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/show_preferences.dart';
import 'package:anilocal/domain/repositories/library_repository.dart';
import 'package:anilocal/domain/repositories/missing_episodes_repository.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/domain/repositories/source_selection_repository.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/domain/repositories/watch_state_repository.dart';

/// The ONE in-memory stand-in for the six repository interfaces `AniLocalApp`
/// and the show page take. Screen tests hand the same instance to every slot.
///
/// Reads come from plain mutable fields ([series], [folders], [episodes],
/// [continuing], [upNext]) so a test can seed a library in the constructor
/// AND mutate it mid-test to simulate a scan; writes that the fakes used to
/// no-op still no-op, except the folder set, which mutates [folders] so a
/// test can watch the app react to a changed set. Every read records its
/// method name in [calls], so a test can assert on what a page did NOT ask
/// for. Subclass to make one read throw (the open-failure tests do).
class FakeLibraryRepository
    implements
        LibraryRepository,
        WatchStateRepository,
        SourceSelectionRepository,
        WatchOrderRepository,
        MissingEpisodesRepository,
        ShowPreferencesRepository {
  FakeLibraryRepository({
    List<Series> series = const [],
    List<String> folders = const [],
    Map<int, List<Episode>> episodes = const {},
    this.episodesCompleter,
    List<ContinueWatching> continuing = const [],
    Map<int, Episode> upNext = const {},
  }) : series = [...series],
       folders = [...folders],
       episodes = {...episodes},
       continuing = [...continuing],
       upNext = {...upNext};

  /// What `allSeries` returns. Mutable so a scan callback can grow it.
  List<Series> series;

  /// Library folder paths, in priority order. `addFolder` / `removeFolder` /
  /// `reorderFolders` mutate it, so `watchedFolders` reflects the change.
  List<String> folders;

  /// Episodes per series id; a series with no entry has none.
  Map<int, List<Episode>> episodes;

  /// When supplied, `episodesFor` hangs on it until the test completes it —
  /// that is how "the DB hasn't answered yet" is simulated.
  final Completer<List<Episode>>? episodesCompleter;

  /// What `continueWatching` returns.
  List<ContinueWatching> continuing;

  /// What `upNextBySeries` returns.
  Map<int, Episode> upNext;

  /// Every read the app made, by method name, in order.
  final List<String> calls = [];

  @override
  Future<List<Series>> allSeries() async {
    calls.add('allSeries');
    return series;
  }

  @override
  Future<List<Episode>> episodesFor(int seriesId) {
    calls.add('episodesFor');
    return episodesCompleter?.future ??
        Future.value(episodes[seriesId] ?? const []);
  }

  // Built from the fields directly rather than via `episodesFor`, so a test
  // holding `episodesFor` open on a completer does not also hang this.
  @override
  Future<Map<int, List<Episode>>> episodesBySeries() async {
    calls.add('episodesBySeries');
    return {for (final s in series) s.seriesId: episodes[s.seriesId] ?? []};
  }

  @override
  Future<Series?> seriesById(int seriesId) async {
    calls.add('seriesById');
    for (final s in series) {
      if (s.seriesId == seriesId) return s;
    }
    return null;
  }

  @override
  Future<int> unmatchedCount() async => (await unmatchedFiles()).length;

  @override
  Future<LibrarySnapshot> snapshot() async {
    calls.add('snapshot');
    return LibrarySnapshot(
      series: await allSeries(),
      episodesBySeries: await episodesBySeries(),
      continueWatching: await continueWatching(),
      upNext: await upNextBySeries(),
      unmatchedCount: await unmatchedCount(),
      hidden: await allHiddenEpisodes(),
      folderCount: folders.length,
    );
  }

  @override
  Future<List<IdentifiedEpisode>> unmatchedFiles() async {
    calls.add('unmatchedFiles');
    return const [];
  }

  @override
  Future<List<LibraryFolder>> watchedFolders() async {
    calls.add('watchedFolders');
    return [for (final p in folders) LibraryFolder(path: p)];
  }

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
  Future<bool> setWatched(Episode episode, {required bool watched}) async =>
      true;

  @override
  Future<void> setWatchedManual(Episode e, {required bool watched}) async {}

  @override
  Future<void> clearProgress(Episode episode) async {}

  @override
  Future<List<ContinueWatching>> continueWatching() async {
    calls.add('continueWatching');
    return continuing;
  }

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
  Future<Map<int, Episode>> upNextBySeries() async {
    calls.add('upNextBySeries');
    return upNext;
  }

  @override
  Future<Set<int>> hiddenEpisodes(int seriesId) async {
    calls.add('hiddenEpisodes');
    return const {};
  }

  @override
  Future<Map<int, Set<int>>> allHiddenEpisodes() async {
    calls.add('allHiddenEpisodes');
    return const {};
  }

  @override
  Future<void> hideEpisodes(int seriesId, List<int> episodes) async {}
  @override
  Future<void> unhideEpisodes(int seriesId, List<int> episodes) async {}

  @override
  Future<ShowPreferences> preferencesFor(int seriesId) async {
    calls.add('preferencesFor');
    return const ShowPreferences();
  }

  @override
  Future<Map<int, ShowPreferences>> allPreferences() async {
    calls.add('allPreferences');
    return const {};
  }

  @override
  Future<void> setPictureMode(int seriesId, PictureMode mode) async {}
  @override
  Future<void> setNextEpisodeHidden(
    int seriesId, {
    required bool hidden,
  }) async {}
  @override
  Future<void> setAllNextEpisodeHidden({required bool hidden}) async {}
}
