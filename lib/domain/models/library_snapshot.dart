import 'package:equatable/equatable.dart';

import 'continue_watching.dart';
import 'episode.dart';
import 'series.dart';

/// Everything the library screen shows, read in ONE pass over the cache.
///
/// The screen used to issue five independent reads per reload — the series
/// list, every series' episodes, continue-watching, up-next and the unmatched
/// count — and each of them loaded the same tables again: `file_cache` five
/// times over for one repaint. A reload is what every scan progress callback,
/// every return from the player and every settings close triggers, so this is
/// the app's hottest read. One snapshot, one materialisation, and the five
/// views are derived from it in memory — they also cannot disagree with each
/// other, which five separate reads could (a card's "Next" against an episode
/// list from a different moment).
class LibrarySnapshot extends Equatable {
  const LibrarySnapshot({
    required this.series,
    required this.episodesBySeries,
    required this.continueWatching,
    required this.upNext,
    required this.unmatchedCount,
    required this.hidden,
    this.folderCount = 0,
  });

  static const empty = LibrarySnapshot(
    series: [],
    episodesBySeries: {},
    continueWatching: [],
    upNext: {},
    unmatchedCount: 0,
    hidden: {},
  );

  /// Every show, sorted by display title — identified shows and the named
  /// placeholders for files not yet identified.
  final List<Series> series;

  /// Every show's episodes (placeholders included), keyed by series id.
  final Map<int, List<Episode>> episodesBySeries;

  /// In-progress episodes, most recent first.
  final List<ContinueWatching> continueWatching;

  /// The next episode to watch per started series.
  final Map<int, Episode> upNext;

  /// CONFIRMED-unmatched files (a source answered "no"); pending placeholders
  /// are not counted — they retry on the next scan.
  final int unmatchedCount;

  /// Hidden episode positions per series (the missing-episodes feature).
  final Map<int, Set<int>> hidden;

  /// How many library folders exist — tells "nothing found" from "nothing
  /// added" when [series] is empty.
  final int folderCount;

  @override
  List<Object?> get props => [
    series,
    episodesBySeries,
    continueWatching,
    upNext,
    unmatchedCount,
    hidden,
    folderCount,
  ];
}
