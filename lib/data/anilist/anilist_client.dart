import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/series.dart';
import 'anilist_mapper.dart';
import 'anilist_queries.dart';

/// Thrown for any AniList request that doesn't yield a usable result.
class AniListException implements Exception {
  const AniListException(this.message);
  final String message;

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
      throw AniListException('Network error contacting AniList: $e');
    }

    if (response.statusCode == 429) {
      throw const AniListException(
        'Rate limited by AniList (HTTP 429). Try again shortly.',
      );
    }
    if (response.statusCode != 200) {
      throw AniListException(
        'AniList request failed: HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) {
      throw AniListException('AniList GraphQL error: ${decoded['errors']}');
    }
    return decoded;
  }

  void dispose() => _http.close();
}
