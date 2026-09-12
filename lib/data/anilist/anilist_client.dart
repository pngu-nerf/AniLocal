import 'package:http/http.dart' as http;

import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';
import '../json_http.dart';
import '../source_exception.dart';
import 'anilist_mapper.dart';
import 'anilist_queries.dart';

/// Thrown for any AniList request that doesn't yield a usable result.
class AniListException extends SourceException {
  const AniListException(super.message, {super.failure});
}

/// Read-only client for AniList's public GraphQL API.
///
/// Seam #3: all AniList access lives behind this class, and every public method
/// returns domain models. No account, no API key — public reads only. Stage 2
/// fetches one hardcoded title; scanning/caching come later.
class AniListClient {
  AniListClient({http.Client? httpClient, Uri? endpoint})
    : _http = httpClient ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse('https://graphql.anilist.co') {
    _json = JsonHttp(
      _http,
      service: 'AniList',
      fail: (m, {required failure}) => AniListException(m, failure: failure),
    );
  }

  final http.Client _http;
  final Uri _endpoint;
  late final JsonHttp _json;

  /// Search for up to [perPage] anime candidates by [title], for client-side
  /// ranking (Stage 3). [formatsIn] restricts formats; pass episodic formats to
  /// cut MUSIC-type false-positives. Returns `[]` when nothing matches.
  Future<List<Series>> searchSeriesCandidates(
    String title, {
    List<String>? formatsIn,
    int perPage = 10,
  }) async {
    final filtering = formatsIn != null && formatsIn.isNotEmpty;
    final body = filtering
        ? {
            'query': mediaCandidatesQueryFiltered,
            'variables': {
              'search': title,
              'perPage': perPage,
              'format': formatsIn,
            },
          }
        : {
            'query': mediaCandidatesQuery,
            'variables': {'search': title, 'perPage': perPage},
          };

    final decoded = await _post(body);
    return _mapMedia(_mediaOf(decoded));
  }

  /// `data.Page.media`, or null when any level is missing or mis-shaped.
  /// Guarded `is` checks, not `as` casts: a cast on `dynamic` throws a
  /// TypeError that no `on AniListException` handler upstream catches.
  static List<dynamic>? _mediaOf(Map<String, dynamic> decoded) {
    final data = decoded['data'];
    final page = data is Map<String, dynamic> ? data['Page'] : null;
    final media = page is Map<String, dynamic> ? page['media'] : null;
    return media is List<dynamic> ? media : null;
  }

  /// The mapper is strict about one thing — an entry must carry an integer
  /// id — and says so with a FormatException; here that becomes the same
  /// malformed-response failure a body that is not JSON produces.
  static List<Series> _mapMedia(List<dynamic>? media) {
    if (media == null) return const [];
    try {
      return seriesListFromMediaList(media);
    } on FormatException catch (e) {
      throw AniListException(
        'Malformed AniList response: $e',
        failure: MetadataFailure.malformedResponse,
      );
    }
  }

  /// Re-fetch known entries BY AniList id (the "refresh metadata" backfill),
  /// batched ≤50 per request (AniList page cap). Returns the mapped [Series];
  /// throws [AniListException] on transport/GraphQL errors.
  Future<List<Series>> fetchSeriesByIds(List<int> ids) async {
    final result = <Series>[];
    for (var i = 0; i < ids.length; i += 50) {
      final end = i + 50 < ids.length ? i + 50 : ids.length;
      final chunk = ids.sublist(i, end);
      final decoded = await _post({
        'query': mediaByIdsQuery,
        'variables': {'ids': chunk, 'perPage': chunk.length},
      });
      result.addAll(_mapMedia(_mediaOf(decoded)));
    }
    return result;
  }

  /// One POST through the shared scaffold; the GraphQL `errors` envelope on
  /// a 200 is the only AniList-specific check left here.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final decoded = await _json.postJson(
      _endpoint,
      body: body,
      errorTextOf: _graphQLErrorText,
    );
    if (decoded['errors'] != null) {
      throw AniListException('AniList GraphQL error: ${decoded['errors']}');
    }
    return decoded;
  }

  /// AniList's own error text from a GraphQL error envelope, or null when the
  /// body isn't one. Doubles as the "did AniList write this?" test, so the
  /// classification and the message can never disagree about the body.
  static String? _graphQLErrorText(String body) {
    final decoded = JsonHttp.tryDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final errors = decoded['errors'];
    if (errors is! List || errors.isEmpty) return null;
    final first = errors.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    return message is String && message.isNotEmpty ? message : null;
  }

  void dispose() => _http.close();
}
