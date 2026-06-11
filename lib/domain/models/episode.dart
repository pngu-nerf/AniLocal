import 'package:equatable/equatable.dart';

import 'episode_source.dart';
import 'skip_range.dart';

/// One playable episode mapped to a [Series].
///
/// Watch state is keyed by EPISODE IDENTITY — [seriesAnilistId] + the
/// AniList-faithful [anchoredNumber] (from Stage 5 fix-match) — NOT by
/// [fileRef]. That identity survives a file move and is what makes one logical
/// episode out of several files: "resume episode 5" means episode 5 regardless
/// of which source file plays it.
///
/// A multi-source episode collapses to a SINGLE Episode whose [sources] lists
/// every copy (priority-ordered); [fileRef] is the resolved active source (a
/// manual override if set, else the highest-priority folder's copy). The UI
/// renders one row and can switch which source plays.
class Episode extends Equatable {
  const Episode({
    required this.number,
    required this.fileRef,
    this.title,
    this.seriesAnilistId = 0,
    this.anchoredNumber = 0,
    this.watched = false,
    this.resumePosition = Duration.zero,
    this.duration = Duration.zero,
    this.sources = const [],
    this.pinnedSourceFolder,
    this.introSkip,
    this.outroSkip,
  });

  /// Display number (a presentation choice — continuous or AniList-faithful).
  final int number;

  /// Local file path to play — the resolved active source.
  final String fileRef;
  final String? title;

  /// Watch-state identity: the AniList entry this episode belongs to, and its
  /// anchored (AniList-faithful) position within that entry.
  final int seriesAnilistId;
  final int anchoredNumber;

  final bool watched;
  final Duration resumePosition;

  /// Total runtime (from watch state), for progress display; zero if unknown.
  final Duration duration;

  /// Every copy of this episode across library folders, priority-ordered. The
  /// active source ([fileRef]) is the one whose [EpisodeSource.fileRef] matches.
  final List<EpisodeSource> sources;

  /// The library folder of an in-effect manual source pin, or null when the
  /// active source is just the folder-priority default (automatic). Lets the
  /// UI show "Automatic" vs a pinned source without guessing.
  final String? pinnedSourceFolder;

  /// Cached intro (OP) / outro (ED) skip windows, or null when AniSkip has no
  /// data for this episode (partial coverage is normal). Read offline.
  final SkipRange? introSkip;
  final SkipRange? outroSkip;

  /// True when the same episode exists in more than one library folder.
  bool get hasMultipleSources => sources.length > 1;

  @override
  List<Object?> get props => [
    number,
    fileRef,
    title,
    seriesAnilistId,
    anchoredNumber,
    watched,
    resumePosition,
    duration,
    sources,
    pinnedSourceFolder,
    introSkip,
    outroSkip,
  ];
}
