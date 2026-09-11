import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../user_agent.dart';
import 'cross_map.dart';

/// Fetches, derives and caches the cross-database id map.
///
/// Source: Fribb/anime-lists `anime-list-mini.json` — a ~5.8MB automated weekly
/// dump with 39,304 entries (20,798 carrying an AniList id). We do NOT keep
/// that file: it is parsed once and reduced to the two id pairs AniLocal reads,
/// which is a fraction of the size and makes every later load cheap.
///
/// **Never throws.** A missing or unfetchable map yields [CrossMap.empty], and
/// every caller treats "unknown id" as the pre-existing behaviour — so a failed
/// fetch degrades to exactly what the app did before, never worse. This is a
/// fill-path helper; the UI never waits on it (seam #2).
class CrossMapStore {
  CrossMapStore({
    http.Client? httpClient,
    required this.directory,
    this.maxAge = const Duration(days: 7),
    Uri? endpoint,
  }) : _http = httpClient ?? http.Client(),
       _endpoint =
           endpoint ??
           Uri.parse(
             'https://raw.githubusercontent.com/Fribb/anime-lists/master/'
             'anime-list-mini.json',
           );

  final http.Client _http;
  final Uri _endpoint;

  /// Where the derived cache lives (injected, like [ArtCache]'s — tests pass a
  /// temp dir, so this class has no path_provider coupling).
  final Future<Directory> Function() directory;

  /// How long a derived cache is considered fresh. The upstream list updates
  /// weekly, so refetching more often than that is pure waste.
  final Duration maxAge;

  /// Format version of the derived file. Bump to invalidate every cache when
  /// the shape changes — cheaper and safer than trying to migrate a cache that
  /// can always be re-derived from upstream.
  static const int _formatVersion = 1;

  CrossMap? _memo;

  /// The map, from memory, then disk, then the network — whichever answers
  /// first. Fresh disk cache means no network at all.
  Future<CrossMap> load({DateTime? now}) async {
    if (_memo != null) return _memo!;

    final at = now ?? DateTime.now();
    final file = await _cacheFile();
    final cached = await _readCache(file);
    if (cached != null && !_isStale(cached.fetchedAt, at)) {
      return _memo = cached.map;
    }

    final fetched = await _fetchAndDerive();
    if (fetched != null) {
      await _writeCache(file, fetched, at);
      return _memo = fetched;
    }

    // Fetch failed. A STALE map still answers most lookups correctly and is
    // strictly better than none — ids don't change, the list only grows.
    return _memo = cached?.map ?? CrossMap.empty;
  }

  bool _isStale(DateTime fetchedAt, DateTime now) =>
      now.difference(fetchedAt) >= maxAge;

  Future<File> _cacheFile() async =>
      File('${(await directory()).path}/crossmap.json');

  Future<({CrossMap map, DateTime fetchedAt})?> _readCache(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['v'] != _formatVersion) return null;
      final fetchedAtMs = decoded['fetchedAtMs'];
      final ids = decoded['ids'];
      if (fetchedAtMs is! int || ids is! Map<String, dynamic>) return null;

      final entries = <int, CrossMapEntry>{};
      for (final entry in ids.entries) {
        final anilistId = int.tryParse(entry.key);
        final pair = entry.value;
        if (anilistId == null || pair is! List || pair.length != 2) continue;
        entries[anilistId] = CrossMapEntry(
          malId: pair[0] is int ? pair[0] as int : null,
          kitsuId: pair[1] is int ? pair[1] as int : null,
        );
      }
      return (
        map: CrossMap(entries),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
      );
    } on Exception {
      // Unreadable or corrupt cache (including a FormatException from
      // jsonDecode, which is an Exception) -> re-derive, never crash.
      return null;
    }
  }

  Future<void> _writeCache(File file, CrossMap map, DateTime at) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'v': _formatVersion,
          'fetchedAtMs': at.millisecondsSinceEpoch,
          'ids': {
            for (final id in map.anilistIds)
              '$id': [map.malFor(id), map.kitsuFor(id)],
          },
        }),
        flush: true,
      );
    } on Exception {
      // A cache we can't write just means we refetch next time. Not fatal.
    }
  }

  /// Download the upstream list and reduce it to the ids we read. Returns null
  /// on any failure — transport, status, or a body that isn't the expected
  /// shape — so the caller can fall back to a stale or empty map.
  Future<CrossMap?> _fetchAndDerive() async {
    final http.Response response;
    try {
      response = await _http.get(
        _endpoint,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': kAniLocalUserAgent,
        },
      );
    } on Exception {
      return null;
    }
    if (response.statusCode != 200) return null;

    final Object? decoded;
    try {
      // BYTES as UTF-8, never `.body` — same charset trap as every other
      // client, and for a 5.8MB body the latin1 detour was a memory cost too.
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;

    final entries = <int, CrossMapEntry>{};
    for (final row in decoded) {
      if (row is! Map<String, dynamic>) continue;
      final anilistId = row['anilist_id'];
      if (anilistId is! int) continue; // no AniList id -> nothing to key on
      final mal = row['mal_id'];
      final kitsu = row['kitsu_id'];
      if (mal is! int && kitsu is! int) continue; // nothing worth storing
      entries[anilistId] = CrossMapEntry(
        malId: mal is int ? mal : null,
        kitsuId: kitsu is int ? kitsu : null,
      );
    }
    return entries.isEmpty ? null : CrossMap(entries);
  }

  void dispose() => _http.close();
}
