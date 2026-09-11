import 'package:equatable/equatable.dart';

import 'external_ids.dart';
import 'picture_mode.dart';
import 'related_series.dart';
import 'titles.dart';

/// A single anime entry, keyed by [seriesId] — AniLocal's own surrogate, not
/// any provider's id.
///
/// Minimal projection of what the UI renders — not a clone of any provider's
/// schema. Mapping from provider DTOs lives in `lib/data/metadata` and the
/// per-provider modules; persistence lives in `lib/data/cache`. This type
/// carries no JSON or DB annotations.
class Series extends Equatable {
  const Series({
    required this.seriesId,
    this.externalIds = ExternalIds.empty,
    required this.titles,
    this.format,
    this.coverImageRef,
    this.episodeCount,
    this.relations = const [],
    this.pending = false,
    this.pictureMode = PictureMode.normal,
    this.nextEpisodeHidden = false,
  });

  /// AniLocal's own opaque identity for this show. Positive values were seeded
  /// from AniList; values at or above `kMintedSeriesIdBase` were minted for a
  /// show no AniList entry covers; NEGATIVE values are PENDING placeholders
  /// derived from the parsed title. See `series_identity.dart` for the bands.
  final int seriesId;

  /// What other databases call this show — AniList, MAL, Kitsu, AniDB. Any of
  /// them may be absent. Distinct from [seriesId]: these are attributes, not
  /// identity, so nothing here may be used as a key.
  ///
  /// Anything rendering "AniList #…" must read `externalIds.anilist` and omit
  /// the label when it is null, rather than printing the surrogate and lying.
  final ExternalIds externalIds;

  final Titles titles;

  /// Series format in AniList's vocabulary, e.g. `TV`, `MOVIE`, `OVA` — other
  /// sources are normalised to it (`normalizeSeriesFormat`).
  final String? format;

  /// Reference to cover art — a remote URL now, a local cached file path once
  /// the cache lands (Stage 4). The UI does not care which.
  final String? coverImageRef;

  /// Total episode count reported by whichever source identified it, when known.
  final int? episodeCount;

  /// Related entries (sequels, prequels, side stories, adaptations).
  final List<RelatedSeries> relations;

  /// True when this is a PLACEHOLDER for a show that's on disk but not yet
  /// identified (no source consulted yet, offline, or the lookup failed). It
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
      titles.english ?? titles.romaji ?? titles.native ?? '#$seriesId';

  @override
  List<Object?> get props => [
    seriesId,
    externalIds,
    titles,
    format,
    coverImageRef,
    episodeCount,
    relations,
    pending,
    pictureMode,
    nextEpisodeHidden,
  ];
}
