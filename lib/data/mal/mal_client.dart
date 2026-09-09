import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/external_ids.dart';
import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';
import '../../domain/models/series_format.dart';
import '../../domain/models/titles.dart';
import '../http_failure.dart';
import '../user_agent.dart';

/// Thrown for any MyAnimeList request that doesn't yield a usable result.
class MalException implements Exception {
  const MalException(this.message, {this.failure = MetadataFailure.service});

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => 'MalException: $message';
}

/// Read-only client for MyAnimeList's official API v2.
///
/// Authenticated with `X-MAL-CLIENT-ID` alone — no user OAuth, no end-user
/// account. The key is the USER'S OWN, never one shipped in the binary: MAL's
/// API agreement §2(a) says a client ID "may not be shared with any third
/// party" and must be "kept secure", which a string inside a downloadable
/// binary cannot be. So this client is inert until someone supplies one.
///
/// **Not live-validated.** Every request needs a key, and none was available
/// while this was written, so the mapping below is built from MAL's published
/// OpenAPI spec rather than an observed 200. The error paths WERE probed live
/// (see [_classify]).
class MalClient {
  MalClient({
    required this.loadClientId,
    http.Client? httpClient,
    Uri? baseUrl,
    Duration? minInterval,
  }) : _http = httpClient ?? http.Client(),
       _base = baseUrl ?? Uri.parse('https://api.myanimelist.net/v2'),
       _minInterval = minInterval ?? const Duration(milliseconds: 1100);

  final http.Client _http;
  final Uri _base;

  /// The user's client ID, read fresh per request so pasting one takes effect
  /// immediately and revoking it stops working immediately.
  final Future<String?> Function() loadClientId;

  /// MAL documents NO rate limit and returns no rate-limit headers, so there is
  /// nothing to back off from adaptively. ~1 req/s is the community's empirical
  /// guidance and the safest default; throttling shows up as a 403, which the
  /// docs list as "DoS detected".
  final Duration _minInterval;

  DateTime? _lastRequest;

  /// The fields MAL must be asked for explicitly — it returns only id, title
  /// and main_picture otherwise.
  static const String _fields =
      'id,title,alternative_titles,media_type,num_episodes,main_picture';

  /// MAL rejects a search shorter than this with `400 {"message":"invalid q"}`.
  /// Checked before sending so a short query is a clean no-match rather than a
  /// failure that would knock this source out of the chain.
  static const int _minQueryLength = 3;

  /// Ranked-candidate search. Returns `[]` for a genuine no-match.
  Future<List<Series>> searchCandidates(
    String title, {
    int perPage = 10,
  }) async {
    if (title.trim().length < _minQueryLength) return const [];
    final decoded = await _get('anime', {
      'q': title.trim(),
      // MAL caps the search page at 100.
      'limit': '${perPage.clamp(1, 100)}',
      'fields': _fields,
    });
    final data = decoded['data'];
    if (data is! List) return const [];
    final out = <Series>[];
    for (final entry in data) {
      // Search nests each result under `node`; the detail endpoint does not.
      if (entry is! Map<String, dynamic>) continue;
      final node = entry['node'];
      if (node is! Map<String, dynamic>) continue;
      final mapped = _seriesFrom(node);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  /// Re-fetch by MAL ids.
  ///
  /// MAL has NO multi-id endpoint — confirmed by its published spec, which
  /// offers only `q`/`limit`/`offset`/`fields` on the list path. So this is one
  /// request per id at ~1/second: a 300-show refresh is minutes of serialized
  /// network. Acceptable only because this source is opt-in and the cheap
  /// sources are asked first.
  Future<List<Series>> fetchByIds(List<int> malIds) async {
    final out = <Series>[];
    for (final id in malIds) {
      final decoded = await _get('anime/$id', const {'fields': _fields});
      final mapped = _seriesFrom(decoded);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  Series? _seriesFrom(Map<String, dynamic> node) {
    final malId = node['id'];
    if (malId is! int) return null;
    final alt = node['alternative_titles'];
    final byLang = alt is Map<String, dynamic> ? alt : const {};
    return Series(
      // Provisional; ensureSeriesId decides the real local identity.
      seriesId: malId,
      externalIds: ExternalIds(mal: malId),
      titles: Titles(
        romaji: _string(node['title']),
        english: _string(byLang['en']),
        native: _string(byLang['ja']),
      ),
      format: normalizeSeriesFormat(_string(node['media_type'])),
      episodeCount: _episodeCount(node['num_episodes']),
      coverImageRef: _pictureFrom(node['main_picture']),
    );
  }

  /// MAL uses `0` to mean UNKNOWN, not "zero episodes". Passing that through
  /// would tell the missing-episodes feature the series has no episodes at all,
  /// instead of leaving the count unknown as AniList's null does.
  static int? _episodeCount(Object? raw) {
    if (raw is! int || raw <= 0) return null;
    return raw;
  }

  /// `en` is frequently the EMPTY STRING rather than null in MAL responses, so
  /// blank must be treated as absent or the UI renders an empty title.
  static String? _string(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static String? _pictureFrom(Object? picture) {
    if (picture is! Map<String, dynamic>) return null;
    return _string(picture['large']) ?? _string(picture['medium']);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final clientId = await loadClientId();
    if (clientId == null || clientId.isEmpty) {
      throw const MalException(
        'No MyAnimeList client ID configured.',
        failure: MetadataFailure.unauthorized,
      );
    }
    await _throttle();

    final http.Response response;
    try {
      response = await _http.get(
        _base.replace(
          pathSegments: [..._base.pathSegments, ...path.split('/')],
          queryParameters: query,
        ),
        headers: {
          'Accept': 'application/json',
          'User-Agent': kAniLocalUserAgent,
          'X-MAL-CLIENT-ID': clientId,
        },
      );
    } on Exception catch (e) {
      throw MalException(
        'Network error contacting MyAnimeList: $e',
        failure: MetadataFailure.connection,
      );
    }

    // MAL does send `charset=UTF-8` and \u-escapes non-ASCII, so this is
    // belt-and-braces rather than a fix — but decoding bytes is the habit that
    // doesn't break when a server lies about its charset, as Kitsu does.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      final detail = _errorMessage(body);
      throw MalException(
        detail == null
            ? 'MyAnimeList request failed: HTTP ${response.statusCode}.'
            : 'MyAnimeList request failed: '
                  'HTTP ${response.statusCode} — $detail',
        failure: _classify(response.statusCode, body),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw MalException('Malformed MyAnimeList response: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MalException('Unexpected MyAnimeList response shape.');
    }
    return decoded;
  }

  /// Attribute a MAL failure, which needs more than the status code.
  ///
  /// Probed live: a missing header returns **403** `{"message":"","error":
  /// "forbidden"}` and a bad key returns **400** `{"message":"Invalid client
  /// id","error":"bad_request"}`. So 403 does NOT mean 401 here, and 400 is not
  /// necessarily a bad request on our part — the body has to be read.
  ///
  /// A 403 once we HAVE sent a key is not an auth problem: MAL's own docs list
  /// 403 as "DoS detected etc.", i.e. throttling. It gets [MetadataFailure
  /// .rateLimited] so the user is told to wait rather than to go re-check a key
  /// that is fine.
  static MetadataFailure _classify(int status, String body) {
    final message = (_errorMessage(body) ?? '').toLowerCase();
    final code = (_errorCode(body) ?? '').toLowerCase();
    if (message.contains('client id') ||
        code == 'invalid_token' ||
        status == 401) {
      return MetadataFailure.unauthorized;
    }
    if (status == 403) return MetadataFailure.rateLimited;
    return classifyHttpFailure(status, carriesProviderError: code.isNotEmpty);
  }

  Future<void> _throttle() async {
    final last = _lastRequest;
    if (last != null) {
      final since = DateTime.now().difference(last);
      if (since < _minInterval) {
        await Future<void>.delayed(_minInterval - since);
      }
    }
    _lastRequest = DateTime.now();
  }

  static String? _errorMessage(String body) => _envelope(body)?['message'];
  static String? _errorCode(String body) => _envelope(body)?['error'];

  /// MAL's error envelope is `{"error": "...", "message": "..."}`; `message`
  /// can be the empty string, so callers must tolerate a blank.
  static Map<String, String>? _envelope(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final error = decoded['error'];
    final message = decoded['message'];
    if (error is! String && message is! String) return null;
    return {
      if (error is String) 'error': error,
      if (message is String) 'message': message,
    };
  }

  void dispose() => _http.close();
}
