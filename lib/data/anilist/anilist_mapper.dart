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
Series seriesFromMediaJson(Map<String, dynamic> media) {
  return Series(
    // seriesId is provisional here: it is what AniList calls the show, and
    // `ensureSeriesId` decides the real local identity (which may already
    // exist under another provider's id, or may need minting).
    seriesId: media['id'] as int,
    // Report EVERY id this response carries, not just AniList's own — that is
    // what lets ensureSeriesId recognise a show some other provider already
    // identified instead of minting a second identity for it.
    externalIds: ExternalIds(
      anilist: media['id'] as int,
      mal: media['idMal'] as int?,
    ),
    titles: _titlesFrom(media['title'] as Map<String, dynamic>?),
    format: media['format'] as String?,
    episodeCount: media['episodes'] as int?,
    coverImageRef: _coverImageFrom(
      media['coverImage'] as Map<String, dynamic>?,
    ),
    relations: _relationsFrom(media['relations'] as Map<String, dynamic>?),
  );
}

/// Maps a `Page.media` list of AniList entries to domain [Series].
List<Series> seriesListFromMediaList(List<dynamic> media) {
  return media
      .map((m) => seriesFromMediaJson(m as Map<String, dynamic>))
      .toList();
}

Titles _titlesFrom(Map<String, dynamic>? title) {
  return Titles(
    romaji: title?['romaji'] as String?,
    english: title?['english'] as String?,
    native: title?['native'] as String?,
  );
}

/// Prefer the largest available cover; AniList may omit some sizes.
String? _coverImageFrom(Map<String, dynamic>? cover) {
  if (cover == null) return null;
  return (cover['extraLarge'] ?? cover['large'] ?? cover['medium']) as String?;
}

List<RelatedSeries> _relationsFrom(Map<String, dynamic>? relations) {
  final edges = relations?['edges'] as List<dynamic>?;
  if (edges == null) return const [];
  final result = <RelatedSeries>[];
  for (final edge in edges) {
    final map = edge as Map<String, dynamic>;
    final node = map['node'] as Map<String, dynamic>?;
    if (node == null) continue;
    result.add(
      RelatedSeries(
        // Genuinely an AniList id: this is AniList's own relation payload, not
        // our surrogate identity. Deliberately NOT renamed with the rest.
        anilistId: node['id'] as int,
        relationType: (map['relationType'] as String?) ?? 'UNKNOWN',
        titles: _titlesFrom(node['title'] as Map<String, dynamic>?),
        format: node['format'] as String?,
      ),
    );
  }
  return result;
}
