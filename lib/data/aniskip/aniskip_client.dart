import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/skip_range.dart';
import '../anilist/anilist_client.dart' show kAniLocalUserAgent;

/// Thrown for an AniSkip request that failed transport-side (network / non-404
/// HTTP). "No data" is NOT an exception — it returns null.
class AniSkipException implements Exception {
  const AniSkipException(this.message);
  final String message;
  @override
  String toString() => 'AniSkipException: $message';
}

/// Read-only client for the AniSkip community API (verified v2:
/// `GET /v2/skip-times/{malId}/{episode}?types=op&types=ed&episodeLength=N`).
///
/// Its own data-layer module (seam: like [AniListClient]) — maps the AniSkip
/// JSON to domain [EpisodeSkips], so no AniSkip shape leaks out. Used ONLY on
/// the scan/fill path; playback reads skip data from the cache, never here.
class AniSkipClient {
  AniSkipClient({http.Client? httpClient, Uri? base})
    : _http = httpClient ?? http.Client(),
      _base = base ?? Uri.parse('https://api.aniskip.com/v2');

  final http.Client _http;
  final Uri _base;

  /// OP/ED windows for ([malId], [episode]). Returns null when AniSkip has no
  /// data (HTTP 404 / `found:false` / no op|ed) — a normal, common case.
  /// [episodeLengthSeconds] 0 means "unknown" (the API accepts it).
  Future<EpisodeSkips?> fetchSkips(
    int malId,
    int episode, {
    int episodeLengthSeconds = 0,
  }) async {
    final uri = _base.replace(
      pathSegments: [..._base.pathSegments, 'skip-times', '$malId', '$episode'],
      queryParameters: {
        'types': ['op', 'ed'],
        'episodeLength': '$episodeLengthSeconds',
      },
    );

    final http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          // A named UA — same reason as AniList: avoid edge/WAF blocks.
          'User-Agent': kAniLocalUserAgent,
        },
      );
    } on Exception catch (e) {
      throw AniSkipException('Network error contacting AniSkip: $e');
    }

    if (response.statusCode == 404) return null; // no data for this episode
    if (response.statusCode == 429) {
      throw const AniSkipException('Rate limited by AniSkip (HTTP 429).');
    }
    if (response.statusCode != 200) {
      throw AniSkipException(
        'AniSkip request failed: HTTP ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw AniSkipException('Malformed AniSkip response: $e');
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['found'] != true) return null;
    final results = decoded['results'];
    if (results is! List) return null;

    SkipRange? intro;
    SkipRange? outro;
    for (final result in results) {
      if (result is! Map<String, dynamic>) continue;
      final interval = result['interval'];
      if (interval is! Map<String, dynamic>) continue;
      final range = SkipRange(
        start: _toDuration(interval['startTime']),
        end: _toDuration(interval['endTime']),
      );
      switch (result['skipType']) {
        case 'op':
          intro = range;
        case 'ed':
          outro = range;
      }
    }
    if (intro == null && outro == null) return null;
    return EpisodeSkips(intro: intro, outro: outro);
  }

  /// AniSkip times are seconds (floats); store as whole milliseconds.
  Duration _toDuration(Object? seconds) {
    final s = (seconds as num?)?.toDouble() ?? 0;
    return Duration(milliseconds: (s * 1000).round());
  }

  void dispose() => _http.close();
}
