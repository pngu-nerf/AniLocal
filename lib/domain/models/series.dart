import 'package:equatable/equatable.dart';

import 'picture_mode.dart';
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
    this.pictureMode = PictureMode.normal,
    this.nextEpisodeHidden = false,
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

  /// How this show's cover is DISPLAYED (a per-show preference surfaced onto the
  /// projection so every cover site renders consistently). The cached
  /// [coverImageRef] is never altered — this only changes how it's shown.
  final PictureMode pictureMode;

  /// When true, the card's "Next episode" button is hidden for this show (a
  /// per-show preference).
  final bool nextEpisodeHidden;

  /// The ONE source of truth for a show's displayed name: English → romaji →
  /// native, falling back to the AniList id (`#123`) when a show somehow has no
  /// title. Every surface (grid, detail, player, continue-watching, fix-match)
  /// reads this so the fallback can't drift between them. NOTE: this is the
  /// *display* title — a search-query seed deliberately differs (romaji-first,
  /// empty fallback) and is not this.
  String get displayTitle =>
      titles.english ?? titles.romaji ?? titles.native ?? '#$anilistId';

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
    pictureMode,
    nextEpisodeHidden,
  ];
}
