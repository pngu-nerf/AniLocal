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
    this.pending = false,
  });

  /// For a real AniList entry this is its positive AniList ID. For a PENDING
  /// placeholder (a show discovered on disk but not yet identified) it is a
  /// stable NEGATIVE synthetic id derived from the parsed title — never a real
  /// AniList id, so it can't collide with one. See [pending].
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

  /// True when this is a PLACEHOLDER for a show that's on disk but not yet
  /// identified (AniList not yet consulted, offline, or the lookup failed). It
  /// carries the parsed title as [titles] and no [coverImageRef]; the UI shows
  /// a named placeholder card. It upgrades in place to a real entry once
  /// identification succeeds on a later scan/refresh. Distinct from a
  /// confirmed-unmatched file (which is never surfaced as a series at all —
  /// it goes to the fix-match screen).
  final bool pending;

  @override
  List<Object?> get props => [
    anilistId,
    titles,
    format,
    coverImageRef,
    episodeCount,
    idMal,
    relations,
    pending,
  ];
}
