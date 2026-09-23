import '../../domain/models/airing_status.dart';
import '../../domain/models/external_ids.dart';
import '../../domain/models/related_series.dart';
import '../../domain/models/series.dart';
import '../../domain/models/titles.dart';

/// Maps AniList's `Media` JSON into the domain [Series].
///
/// This is the data-layer boundary (seam #3): the AniList response shape is
/// known here and nowhere else. Everything past this returns domain models, so
/// no AniList type leaks into the rest of the app. Pure and network-free, so
/// it's unit-testable from a captured response.
///
/// Every read is GUARDED, like the Kitsu, Jikan and MAL mappers. This one used
/// unchecked casts, and a cast on `dynamic` throws a `TypeError` — an `Error`,
/// not an `Exception` — which escaped every catch on the scan path and aborted
/// the whole run before the cache-preserving outage guard could act. A field
/// of the wrong shape is now null; only a missing or non-integer `id` is
/// fatal, as a [FormatException] the client turns into a malformed-response
/// failure.
Series seriesFromMediaJson(Map<String, dynamic> media) {
  final id = _int(media['id']);
  if (id == null) {
    throw const FormatException('AniList media entry without an integer id');
  }
  return Series(
    // seriesId is provisional here: it is what AniList calls the show, and
    // `ensureSeriesId` decides the real local identity (which may already
    // exist under another provider's id, or may need minting).
    seriesId: id,
    // Report EVERY id this response carries, not just AniList's own — that is
    // what lets ensureSeriesId recognise a show some other provider already
    // identified instead of minting a second identity for it.
    externalIds: ExternalIds(anilist: id, mal: _int(media['idMal'])),
    titles: _titlesFrom(_map(media['title'])),
    format: _string(media['format']),
    episodeCount: _int(media['episodes']),
    coverImageRef: _coverImageFrom(_map(media['coverImage'])),
    relations: _relationsFrom(_map(media['relations'])),
    airingStatus: AiringStatus.fromAniList(_string(media['status'])),
    nextAiringAt: _epochSeconds(_map(media['nextAiringEpisode'])?['airingAt']),
    nextAiringEpisode: _int(_map(media['nextAiringEpisode'])?['episode']),
    endDate: _fuzzyDate(_map(media['endDate'])),
  );
}

/// AniList's `airingAt` is epoch SECONDS; stored and compared as an instant.
DateTime? _epochSeconds(Object? v) =>
    v is int ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;

/// AniList's `FuzzyDate`: any part may be null. A year alone is still a date
/// (Jan 1); no year is no date.
DateTime? _fuzzyDate(Map<String, dynamic>? d) {
  final year = _int(d?['year']);
  if (year == null) return null;
  return DateTime(year, _int(d?['month']) ?? 1, _int(d?['day']) ?? 1);
}

/// Maps a `Page.media` list of AniList entries to domain [Series]. Entries
/// that are not objects (a `null` in the list) are skipped, not fatal.
List<Series> seriesListFromMediaList(List<dynamic> media) => [
  for (final m in media)
    if (m is Map<String, dynamic>) seriesFromMediaJson(m),
];

int? _int(Object? v) => v is int ? v : null;
String? _string(Object? v) => v is String ? v : null;
Map<String, dynamic>? _map(Object? v) => v is Map<String, dynamic> ? v : null;

Titles _titlesFrom(Map<String, dynamic>? title) => Titles(
  romaji: _string(title?['romaji']),
  english: _string(title?['english']),
  native: _string(title?['native']),
);

/// Prefer the largest available cover; AniList may omit some sizes.
String? _coverImageFrom(Map<String, dynamic>? cover) {
  if (cover == null) return null;
  return _string(cover['extraLarge']) ??
      _string(cover['large']) ??
      _string(cover['medium']);
}

List<RelatedSeries> _relationsFrom(Map<String, dynamic>? relations) {
  final edges = relations?['edges'];
  if (edges is! List) return const [];
  final result = <RelatedSeries>[];
  for (final edge in edges) {
    final map = _map(edge);
    final node = _map(map?['node']);
    final nodeId = _int(node?['id']);
    if (node == null || nodeId == null) continue;
    result.add(
      RelatedSeries(
        // Genuinely an AniList id: this is AniList's own relation payload, not
        // our surrogate identity. Deliberately NOT renamed with the rest.
        anilistId: nodeId,
        relationType: _string(map?['relationType']) ?? 'UNKNOWN',
        titles: _titlesFrom(_map(node['title'])),
        format: _string(node['format']),
      ),
    );
  }
  return result;
}
