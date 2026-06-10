import 'package:equatable/equatable.dart';

import 'series.dart';

/// Confidence band for an auto-match. Derived from a raw similarity score —
/// the band is for at-a-glance triage; the score is the honest signal. Wrong
/// matches are expected (Stage 5 adds manual fix-match); we surface uncertainty
/// rather than fake certainty.
enum MatchConfidence { none, low, medium, high }

/// The Stage 3 identification result for one video file: what the filename
/// parsed to, and which AniList [Series] (if any) it was matched to.
///
/// A domain model so the UI can display it without importing scanner types
/// (seam #1). No caching/persistence here — that's Stage 4.
class IdentifiedEpisode extends Equatable {
  const IdentifiedEpisode({
    required this.filePath,
    required this.parsedTitle,
    this.parsedEpisodeNumber,
    this.releaseGroup,
    this.series,
    this.matchScore = 0,
  });

  /// Absolute path to the video file.
  final String filePath;

  /// Title text the parser extracted from the filename (pre-match).
  final String parsedTitle;

  /// Episode number parsed from the filename, if any (null for movies/specials
  /// or when parsing couldn't find one).
  final int? parsedEpisodeNumber;

  /// Release group parsed from a leading `[Group]` tag, if present.
  final String? releaseGroup;

  /// The best AniList match, or null when no acceptable candidate was found.
  final Series? series;

  /// Raw title-similarity score of [series] to [parsedTitle], 0–1.
  final double matchScore;

  String get fileName {
    final i = filePath.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? filePath : filePath.substring(i + 1);
  }

  MatchConfidence get confidence {
    if (series == null) return MatchConfidence.none;
    if (matchScore >= 0.80) return MatchConfidence.high;
    if (matchScore >= 0.55) return MatchConfidence.medium;
    return MatchConfidence.low;
  }

  @override
  List<Object?> get props => [
    filePath,
    parsedTitle,
    parsedEpisodeNumber,
    releaseGroup,
    series,
    matchScore,
  ];
}
