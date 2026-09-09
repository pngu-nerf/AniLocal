import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/external_ids.dart';
import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';
import '../../domain/models/series_format.dart';
import '../../domain/models/titles.dart';
import '../http_failure.dart';
import '../user_agent.dart';

/// Thrown for any Kitsu request that doesn't yield a usable result.
class KitsuException implements Exception {
  const KitsuException(this.message, {this.failure = MetadataFailure.service});

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => 'KitsuException: $message';
}

/// Read-only client for Kitsu's public JSON:API.
///
/// No account, no key, no registration — the only rich source of that kind
/// still answering while AniList's API is disabled.
///
/// **Every request asks for `include=mappings`.** Kitsu is slow (1.5–10s
/// observed), so resolving a candidate's AniList/MAL ids with a second request
/// each would be unusable. The mappings ride along in `included`, linked by
/// `relationships.mappings.data`, which is what lets the provider report every
/// id it knows in one round trip — and that in turn is what stops
/// `ensureSeriesId` minting a duplicate identity for a show AniList already
/// named.
class KitsuClient {
  KitsuClient({http.Client? httpClient, Uri? baseUrl})
    : _http = httpClient ?? http.Client(),
      _base = baseUrl ?? Uri.parse('https://kitsu.io/api/edge');

  final http.Client _http;
  final Uri _base;

  /// Ranked-candidate search. Returns `[]` for a genuine no-match.
  Future<List<Series>> searchCandidates(String title, {int perPage = 10}) =>
      _fetchList({
        'filter[text]': title,
        'page[limit]': '$perPage',
        'include': 'mappings',
      });

  /// Re-fetch by Kitsu's own ids (the refresh backfill).
  Future<List<Series>> fetchByIds(List<int> kitsuIds) async {
    if (kitsuIds.isEmpty) return const [];
    final result = <Series>[];
    // Kitsu caps a page at 20; chunk so a large library still refreshes.
    for (var i = 0; i < kitsuIds.length; i += 20) {
      final end = i + 20 < kitsuIds.length ? i + 20 : kitsuIds.length;
      final chunk = kitsuIds.sublist(i, end);
      result.addAll(
        await _fetchList({
          'filter[id]': chunk.join(','),
          'page[limit]': '${chunk.length}',
          'include': 'mappings',
        }),
      );
    }
    return result;
  }

  Future<List<Series>> _fetchList(Map<String, String> query) async {
    final decoded = await _get(query);
    final data = decoded['data'];
    if (data is! List) return const [];

    // mapping id -> (site, externalId), so each anime can resolve its own.
    final mappings = <String, MapEntry<String, String>>{};
    final included = decoded['included'];
    if (included is List) {
      for (final entry in included) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['type'] != 'mappings') continue;
        final attrs = entry['attributes'];
        if (attrs is! Map<String, dynamic>) continue;
        final site = attrs['externalSite'];
        final external = attrs['externalId'];
        final id = entry['id'];
        if (site is String && external is String && id is String) {
          mappings[id] = MapEntry(site, external);
        }
      }
    }

    final series = <Series>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final mapped = _seriesFrom(entry, mappings);
      if (mapped != null) series.add(mapped);
    }
    return series;
  }

  Series? _seriesFrom(
    Map<String, dynamic> entry,
    Map<String, MapEntry<String, String>> mappings,
  ) {
    final kitsuId = int.tryParse('${entry['id']}');
    if (kitsuId == null) return null;
    final attrs = entry['attributes'];
    if (attrs is! Map<String, dynamic>) return null;

    final titles = attrs['titles'];
    final byLang = titles is Map<String, dynamic> ? titles : const {};
    return Series(
      // Provisional: ensureSeriesId decides the real local identity.
      seriesId: kitsuId,
      externalIds: _idsFor(entry, mappings, kitsuId),
      titles: Titles(
        // Kitsu's en_jp IS the romanised title, and en the English one — the
        // same split AniList calls romaji/english.
        romaji: _string(byLang['en_jp']) ?? _string(attrs['canonicalTitle']),
        english: _string(byLang['en']),
        native: _string(byLang['ja_jp']),
      ),
      format: normalizeSeriesFormat(_string(attrs['subtype'])),
      episodeCount: attrs['episodeCount'] is int
          ? attrs['episodeCount'] as int
          : null,
      coverImageRef: _posterFrom(attrs['posterImage']),
    );
  }

  ExternalIds _idsFor(
    Map<String, dynamic> entry,
    Map<String, MapEntry<String, String>> mappings,
    int kitsuId,
  ) {
    int? anilist;
    int? mal;
    int? anidb;
    final rel = entry['relationships'];
    final mappingsRel = rel is Map<String, dynamic> ? rel['mappings'] : null;
    final linked = mappingsRel is Map<String, dynamic>
        ? mappingsRel['data']
        : null;
    if (linked is List) {
      for (final ref in linked) {
        if (ref is! Map<String, dynamic>) continue;
        final mapping = mappings['${ref['id']}'];
        if (mapping == null) continue;
        final value = int.tryParse(mapping.value);
        if (value == null) continue;
        switch (mapping.key) {
          case 'anilist/anime':
            anilist = value;
          case 'myanimelist/anime':
            mal = value;
          case 'anidb':
            anidb = value;
        }
      }
    }
    return ExternalIds(
      anilist: anilist,
      mal: mal,
      kitsu: kitsuId,
      anidb: anidb,
    );
  }

  static String? _string(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static String? _posterFrom(Object? poster) {
    if (poster is! Map<String, dynamic>) return null;
    for (final size in ['large', 'medium', 'original', 'small']) {
      final url = _string(poster[size]);
      if (url != null) return url;
    }
    return null;
  }

  /// Shared GET + error handling. Returns the decoded JSON:API body.
  Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    final http.Response response;
    try {
      response = await _http.get(
        _base.replace(
          pathSegments: [..._base.pathSegments, 'anime'],
          queryParameters: query,
        ),
        headers: const {
          'Accept': 'application/vnd.api+json',
          'User-Agent': kAniLocalUserAgent,
        },
      );
    } on Exception catch (e) {
      // No HTTP response at all: the request never reached Kitsu.
      throw KitsuException(
        'Network error contacting Kitsu: $e',
        failure: MetadataFailure.connection,
      );
    }

    // Decode the BYTES as UTF-8, never `response.body`. Kitsu returns raw
    // multi-byte UTF-8 with no `charset` in its content-type, and Dart's http
    // package falls back to latin1 in that case — which turns every Japanese
    // title into mojibake. JSON is UTF-8 by specification (RFC 8259), so this
    // is correct regardless of what any server declares.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      final detail = _errorText(body);
      throw KitsuException(
        detail == null
            ? 'Kitsu request failed: HTTP ${response.statusCode}.'
            : 'Kitsu request failed: HTTP ${response.statusCode} — $detail',
        failure: classifyHttpFailure(
          response.statusCode,
          carriesProviderError: detail != null,
        ),
      );
    }

    // Guarded, not a cast — a 200 carrying an edge interstitial must not throw
    // a bare FormatException past every `on MetadataException` upstream.
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw KitsuException('Malformed Kitsu response: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const KitsuException('Unexpected Kitsu response shape.');
    }
    if (decoded['errors'] != null) {
      throw KitsuException('Kitsu API error: ${decoded['errors']}');
    }
    return decoded;
  }

  /// Kitsu's own error text from a JSON:API error envelope, or null when the
  /// body isn't one. Doubles as the "did Kitsu write this?" test.
  static String? _errorText(String body) {
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
    if (first is! Map<String, dynamic>) return null;
    return _string(first['detail']) ?? _string(first['title']);
  }

  void dispose() => _http.close();
}
