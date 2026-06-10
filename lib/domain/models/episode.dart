import 'package:equatable/equatable.dart';

/// One playable episode mapped to a [Series].
///
/// Watch state is keyed by EPISODE IDENTITY — [seriesAnilistId] + the
/// AniList-faithful [anchoredNumber] (from Stage 5 fix-match) — NOT by
/// [fileRef]. That identity survives a file move and serves the future
/// multi-source stage: "resume episode 5" means episode 5 regardless of which
/// source file plays it.
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
  });

  /// Display number (a presentation choice — continuous or AniList-faithful).
  final int number;

  /// Local file path to play.
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
  ];
}
