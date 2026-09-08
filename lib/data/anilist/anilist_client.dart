import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';
import 'anilist_mapper.dart';
import 'anilist_queries.dart';

/// Thrown for any AniList request that doesn't yield a usable result.
class AniListException implements Exception {
  const AniListException(
    this.message, {
    this.failure = MetadataFailure.service,
  });

  final String message;

  /// Whose end the fault is on, for the UI to render. Defaults to
  /// [MetadataFailure.service] because blaming the user's connection without
  /// evidence is the worse error: it sends them to debug a working network.
  final MetadataFailure failure;

  @override
  String toString() => 'AniListException: $message';
}

/// Identifies the app to AniList. REQUIRED: AniList sits behind Cloudflare,
/// which 403s requests sending the `http` package's default user agent. A
/// stable, named UA gets through (and is good public-API citizenship).
const String kAniLocalUserAgent = 'AniLocal/1.0';

/// Read-only client for AniList's public GraphQL API.
///
/// Seam #3: all AniList access lives behind this class, and every public method
/// returns domain models. No account, no API key — public reads only. Stage 2
/// fetches one hardcoded title; scanning/caching come later.
class AniListClient {
  AniListClient({http.Client? httpClient, Uri? endpoint})
    : _http = httpClient ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse('https://graphql.anilist.co');

  final http.Client _http;
  final Uri _endpoint;

  /// Search for a single anime by [title] and map the best match to [Series].
  ///
  /// [formatsIn] optionally restricts results to an allow-list of AniList
  /// formats (e.g. `['TV', 'MOVIE', 'OVA']`); null means no filter (everything,
  /// including MUSIC PVs). Throws [AniListException] on transport errors, rate
  /// limiting, GraphQL errors, or no match.
  Future<Series> fetchSeriesByTitle(
    String title, {
    List<String>? formatsIn,
  }) async {
    // AniList 500s on an explicit `format_in: null`, so only use the filtered
    // query (and send the variable) when a non-empty filter is supplied.
    final filtering = formatsIn != null && formatsIn.isNotEmpty;
    final body = filtering
        ? {
            'query': mediaSearchQueryFiltered,
            'variables': {'search': title, 'format': formatsIn},
          }
        : {
            'query': mediaSearchQuery,
            'variables': {'search': title},
          };

    final decoded = await _post(body);
    final data = decoded['data'] as Map<String, dynamic>?;
    final media = data?['Media'] as Map<String, dynamic>?;
    if (media == null) {
      throw AniListException('No AniList match for "$title".');
    }

    return seriesFromMediaJson(media);
  }

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
    final page =
        (decoded['data'] as Map<String, dynamic>?)?['Page']
            as Map<String, dynamic>?;
    final media = page?['media'] as List<dynamic>?;
    if (media == null) return const [];
    return seriesListFromMediaList(media);
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
      final page =
          (decoded['data'] as Map<String, dynamic>?)?['Page']
              as Map<String, dynamic>?;
      final media = page?['media'] as List<dynamic>?;
      if (media != null) result.addAll(seriesListFromMediaList(media));
    }
    return result;
  }

  /// Shared POST + error handling. Returns the decoded JSON body.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _http.post(
        _endpoint,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Without this, AniList's Cloudflare returns HTTP 403.
          'User-Agent': kAniLocalUserAgent,
        },
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      // No HTTP response at all: the request never reached AniList, so the
      // fault is on this side of the wire.
      throw AniListException(
        'Network error contacting AniList: $e',
        failure: MetadataFailure.connection,
      );
    }

    if (response.statusCode != 200) {
      final detail = _graphQLErrorText(response.body);
      throw AniListException(
        detail == null
            ? 'AniList request failed: HTTP ${response.statusCode}.'
            : 'AniList request failed: HTTP ${response.statusCode} — $detail',
        failure: _classifyStatus(response.statusCode, detail != null),
      );
    }

    // Guarded, not a cast: a 200 carrying HTML (an edge interstitial) would
    // otherwise throw a bare FormatException that escapes every `on
    // AniListException` handler upstream — aborting the whole scan and skipping
    // the cache-preserving unreachable guard in LibrarySync.
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw AniListException('Malformed AniList response: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AniListException('Unexpected AniList response shape.');
    }
    if (decoded['errors'] != null) {
      throw AniListException('AniList GraphQL error: ${decoded['errors']}');
    }
    return decoded;
  }

  /// Whose end a non-200 points at. [isAniListBody] means the response carried
  /// AniList's own GraphQL error envelope, which only AniList writes.
  static MetadataFailure _classifyStatus(int status, bool isAniListBody) {
    if (status == 429) return MetadataFailure.rateLimited;
    // 5xx is server-side by definition, whoever rendered the page.
    if (status >= 500) return MetadataFailure.service;
    // A 4xx speaking GraphQL is AniList deliberately refusing — today's
    // "API temporarily disabled" outage lands here. A 4xx with any other body
    // was written by something between the user and AniList (proxy, VPN,
    // captive portal, or the Cloudflare UA block this client works around).
    return isAniListBody ? MetadataFailure.service : MetadataFailure.blocked;
  }

  /// AniList's own error text from a GraphQL error envelope, or null when the
  /// body isn't one. Doubles as the "did AniList write this?" test, so the
  /// classification and the message can never disagree about the body.
  static String? _graphQLErrorText(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final errors = decoded['errors'];
    if (errors is! List || errors.isEmpty) return null;
    final first = errors.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    return message is String && message.isNotEmpty ? message : null;
  }

  void dispose() => _http.close();
}
