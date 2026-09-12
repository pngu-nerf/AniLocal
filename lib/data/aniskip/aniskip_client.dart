import 'package:anilocal/data/anilist/anilist_client.dart' show AniListClient;
import 'package:http/http.dart' as http;

import '../../domain/models/skip_range.dart';
import '../json_http.dart';
import '../request_throttle.dart';
import '../source_exception.dart';

/// Thrown for an AniSkip request that failed transport-side (network / non-404
/// HTTP). "No data" is NOT an exception — it returns null.
class AniSkipException extends SourceException {
  const AniSkipException(super.message, {super.failure});
}

/// Read-only client for the AniSkip community API (verified v2:
/// `GET /v2/skip-times/{malId}/{episode}?types=op&types=ed&episodeLength=N`).
///
/// Its own data-layer module (seam: like [AniListClient]) — maps the AniSkip
/// JSON to domain [EpisodeSkips], so no AniSkip shape leaks out. Used ONLY on
/// the scan/fill path; playback reads skip data from the cache, never here.
class AniSkipClient {
  AniSkipClient({http.Client? httpClient, Uri? base, Duration? minInterval})
    : _http = httpClient ?? http.Client(),
      _base = base ?? Uri.parse('https://api.aniskip.com/v2') {
    _json = JsonHttp(
      _http,
      service: 'AniSkip',
      fail: (m, {required failure}) => AniSkipException(m, failure: failure),
      // AniSkip documents no limit. A scan asks once per episode, hundreds in
      // a row for a new library; spacing them is courtesy to a volunteer
      // service, not compliance, and 5/s is far above what a scan needs.
      throttle: RequestThrottle(
        minInterval ?? const Duration(milliseconds: 200),
      ),
    );
  }

  final http.Client _http;
  final Uri _base;
  late final JsonHttp _json;

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

    // 404 is AniSkip's "no data for this episode" — a normal answer.
    final decoded = await _json.getJsonOrNull(uri);
    if (decoded == null) return null;
    final results = decoded['results'];
    if (results is! List) return null;

    SkipRange? intro;
    SkipRange? outro;
    for (final result in results) {
      if (result is! Map<String, dynamic>) continue;
      final interval = result['interval'];
      if (interval is! Map<String, dynamic>) continue;
      final start = _toDuration(interval['startTime']);
      final end = _toDuration(interval['endTime']);
      // A time of the wrong type (or an inverted window) drops THIS window;
      // the old cast threw a TypeError that killed the whole scan.
      if (start == null || end == null || end <= start) continue;
      final range = SkipRange(start: start, end: end);
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

  /// AniSkip times are seconds (floats); store as whole milliseconds. Null
  /// when the wire value is not a number.
  Duration? _toDuration(Object? seconds) =>
      seconds is num ? Duration(milliseconds: (seconds * 1000).round()) : null;

  void dispose() => _http.close();
}
