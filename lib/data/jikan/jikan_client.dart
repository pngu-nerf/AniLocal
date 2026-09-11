import 'dart:convert';

import 'package:http/http.dart' as http;

import '../request_throttle.dart';

import '../../domain/models/external_ids.dart';
import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';
import '../../domain/models/series_format.dart';
import '../../domain/models/titles.dart';
import '../http_failure.dart';
import '../user_agent.dart';

/// Thrown for any Jikan request that doesn't yield a usable result.
class JikanException implements Exception {
  const JikanException(this.message, {this.failure = MetadataFailure.service});

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => 'JikanException: $message';
}

/// Read-only client for Jikan, the community proxy in front of MyAnimeList.
///
/// The DATA is MAL's, which is the richest of the four. The TRANSPORT is one
/// volunteer-run service with no SLA, measured at roughly 30% success while
/// this was written (0/12, then 0/5, then 1/3, then fully 504). MAL itself was
/// up throughout, so the flakiness is Jikan's own infrastructure.
///
/// That is why this source is a FALLBACK and never a source of truth: it is
/// worth having when everything else is down, and not worth building a
/// library's metadata on. Getting MAL data reliably means the official API and
/// a client ID the user supplies — a separate, opt-in source.
///
/// Jikan publishes only MAL ids, so a bare answer would mint a fresh identity
/// for a show AniList already names. The provider adapter closes that with the
/// cross-map (MAL -> AniList); this client just reports what Jikan said.
class JikanClient {
  JikanClient({http.Client? httpClient, Uri? baseUrl, Duration? minInterval})
    : _http = httpClient ?? http.Client(),
      _base = baseUrl ?? Uri.parse('https://api.jikan.moe/v4'),
      _throttler = RequestThrottle(
        minInterval ?? const Duration(milliseconds: 350),
      );

  final http.Client _http;
  final Uri _base;

  /// Jikan documents 3 requests/second. Requests are spaced by at least this
  /// much so a scan can't trip the limiter and turn a working source into a
  /// failing one. Injectable so tests don't sleep.

  final RequestThrottle _throttler;

  /// Ranked-candidate search. Returns `[]` for a genuine no-match.
  Future<List<Series>> searchCandidates(
    String title, {
    int perPage = 10,
  }) async {
    final decoded = await _get('anime', {
      'q': title,
      'limit': '$perPage',
      // Jikan's own relevance ordering; ranking still happens client-side.
      'order_by': 'members',
      'sort': 'desc',
    });
    final data = decoded['data'];
    if (data is! List) return const [];
    final out = <Series>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final mapped = _seriesFrom(entry);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  /// Re-fetch by MAL ids.
  ///
  /// Jikan has NO batch-by-id endpoint, so this is one request per id, spaced
  /// by the rate limit. On a large library that is slow enough to matter —
  /// acceptable only because this source is a fallback that runs when the ones
  /// above it have already failed.
  Future<List<Series>> fetchByIds(List<int> malIds) async {
    final out = <Series>[];
    for (final id in malIds) {
      final decoded = await _get('anime/$id', const {});
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) continue;
      final mapped = _seriesFrom(data);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  Series? _seriesFrom(Map<String, dynamic> entry) {
    final malId = entry['mal_id'];
    if (malId is! int) return null;
    return Series(
      // Provisional; ensureSeriesId decides the real local identity, and the
      // adapter enriches these ids from the cross-map first.
      seriesId: malId,
      externalIds: ExternalIds(mal: malId),
      titles: Titles(
        // MAL's `title` is the romanised one; `title_english` and
        // `title_japanese` line up with the other sources' english/native.
        romaji: _string(entry['title']),
        english: _string(entry['title_english']),
        native: _string(entry['title_japanese']),
      ),
      format: normalizeSeriesFormat(_string(entry['type'])),
      episodeCount: entry['episodes'] is int ? entry['episodes'] as int : null,
      coverImageRef: _imageFrom(entry['images']),
    );
  }

  static String? _string(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static String? _imageFrom(Object? images) {
    if (images is! Map<String, dynamic>) return null;
    for (final format in ['jpg', 'webp']) {
      final byFormat = images[format];
      if (byFormat is! Map<String, dynamic>) continue;
      for (final size in ['large_image_url', 'image_url', 'small_image_url']) {
        final url = _string(byFormat[size]);
        if (url != null) return url;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    await _throttle();

    final http.Response response;
    try {
      response = await _http.get(
        _base.replace(
          pathSegments: [..._base.pathSegments, ...path.split('/')],
          queryParameters: query.isEmpty ? null : query,
        ),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': kAniLocalUserAgent,
        },
      );
    } on Exception catch (e) {
      throw JikanException(
        'Network error contacting Jikan: $e',
        failure: MetadataFailure.connection,
      );
    }

    // Decode the BYTES as UTF-8: Jikan sends `application/json` with no
    // charset, and Dart's http package falls back to latin1 in that case,
    // which mojibakes every Japanese title. JSON is UTF-8 per RFC 8259.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      final detail = _errorText(body);
      throw JikanException(
        detail == null
            ? 'Jikan request failed: HTTP ${response.statusCode}.'
            : 'Jikan request failed: HTTP ${response.statusCode} — $detail',
        // Jikan's characteristic failure is a 504 from its own gateway, which
        // classifies as `service` — their end, not the user's. That is the
        // honest attribution: MAL is usually fine underneath.
        failure: classifyHttpFailure(
          response.statusCode,
          carriesProviderError: detail != null,
        ),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw JikanException('Malformed Jikan response: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const JikanException('Unexpected Jikan response shape.');
    }
    return decoded;
  }

  /// Space requests out so a scan can't trip Jikan's 3/second limiter.
  Future<void> _throttle() => _throttler.wait();

  /// Jikan's error envelope, or null when the body isn't one.
  static String? _errorText(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return _string(decoded['message']) ?? _string(decoded['error']);
  }

  void dispose() => _http.close();
}
