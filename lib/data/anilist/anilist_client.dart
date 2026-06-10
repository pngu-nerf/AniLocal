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

    final http.Response response;
    try {
      response = await _http.post(
        _endpoint,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
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

    final data = decoded['data'] as Map<String, dynamic>?;
    final media = data?['Media'] as Map<String, dynamic>?;
    if (media == null) {
      throw AniListException('No AniList match for "$title".');
    }

    return seriesFromMediaJson(media);
  }

  void dispose() => _http.close();
}
