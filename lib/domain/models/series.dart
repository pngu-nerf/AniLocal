import 'package:equatable/equatable.dart';

import 'related_series.dart';
import 'titles.dart';

/// A single anime entry, keyed by its AniList ID.
///
/// Minimal projection of what the UI renders — not a clone of the AniList
/// schema. Mapping from AniList DTOs lives in `lib/data/anilist`; persistence
/// lives in `lib/data/cache`. This type carries no JSON or DB annotations.
class Series extends Equatable {
  const Series({
    required this.anilistId,
    required this.titles,
    this.format,
    this.coverImageRef,
    this.episodeCount,
    this.idMal,
    this.relations = const [],
  });

  final int anilistId;

  /// MyAnimeList id (AniList's `idMal` cross-reference). Used only to query
  /// AniSkip (keyed by MAL id); null when AniList has no MAL mapping.
  final int? idMal;

  final Titles titles;

  /// AniList format, e.g. `TV`, `MOVIE`, `OVA`. Free-form for now.
  final String? format;

  /// Reference to cover art — a remote URL now, a local cached file path once
  /// the cache lands (Stage 4). The UI does not care which.
  final String? coverImageRef;

  /// Total episode count reported by AniList, when known.
  final int? episodeCount;

  /// Related entries (sequels, prequels, side stories, adaptations).
  final List<RelatedSeries> relations;

  @override
  List<Object?> get props => [
    anilistId,
    titles,
    format,
    coverImageRef,
    episodeCount,
    idMal,
    relations,
  ];
}
