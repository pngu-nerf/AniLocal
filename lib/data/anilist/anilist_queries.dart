/// GraphQL query strings for AniList's public API.
///
/// Kept as plain strings (no `graphql_flutter`): AniList reads are simple POSTs.
library;

/// The `Media` fields the UI projects, plus `relations` (fetched now, surfaced
/// as watch-order later). Shared by the filtered/unfiltered search queries.
const String _mediaFields = r'''
    id
    format
    episodes
    title {
      romaji
      english
      native
    }
    coverImage {
      extraLarge
      large
      medium
    }
    relations {
      edges {
        relationType
        node {
          id
          format
          type
          title {
            romaji
            english
            native
          }
        }
      }
    }
''';

/// Search for a single anime [Media] by title (no format filter).
///
/// `$search` is supplied via GraphQL variables, never string-interpolated.
const String mediaSearchQuery =
    '''
query (\$search: String) {
  Media(search: \$search, type: ANIME) {
$_mediaFields
  }
}
''';

/// Same as [mediaSearchQuery] but restricts to a `format_in` allow-list.
///
/// Used only when a non-empty format filter is supplied — AniList returns
/// HTTP 500 for an explicit `format_in: null`, so the unfiltered path must omit
/// the argument entirely rather than pass null.
const String mediaSearchQueryFiltered =
    '''
query (\$search: String, \$format: [MediaFormat]) {
  Media(search: \$search, type: ANIME, format_in: \$format) {
$_mediaFields
  }
}
''';

/// Multi-candidate search (a `Page` of media) for Stage 3 matching — the top
/// hit alone is unreliable, so we rank a handful client-side. `SEARCH_MATCH`
/// orders by relevance; we still re-rank by title similarity.
const String mediaCandidatesQuery =
    '''
query (\$search: String, \$perPage: Int) {
  Page(page: 1, perPage: \$perPage) {
    media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
$_mediaFields
    }
  }
}
''';

/// Filtered variant of [mediaCandidatesQuery] (omits `format_in` when null —
/// see the note on [mediaSearchQueryFiltered]).
const String mediaCandidatesQueryFiltered =
    '''
query (\$search: String, \$perPage: Int, \$format: [MediaFormat]) {
  Page(page: 1, perPage: \$perPage) {
    media(search: \$search, type: ANIME, format_in: \$format, sort: SEARCH_MATCH) {
$_mediaFields
    }
  }
}
''';
