import 'dart:io';

import '../data/metadata/metadata_provider.dart';
import '../domain/models/source_preference.dart';
import '../data/cache/art_cache.dart';
import '../data/cache/cache_database.dart';
import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';

/// Applies user match corrections. This is the ONLY writer of `match_overrides`
/// — LibrarySync (the auto-matcher) has no reference to it, so a rescan cannot
/// overwrite an override (seam #5, by structure).
///
/// Overrides are keyed by the file's content fingerprint (size + mtime), so
/// they follow a moved/renamed file with no extra bookkeeping.
/// A candidate that cannot be given a local identity — it carries no external
/// id at all. No shipped provider produces one; this exists so the only
/// alternative, writing the provider's provisional id into the AniList-seeded
/// band as if it were ours, can never happen silently.
class FixMatchException implements Exception {
  const FixMatchException(this.message);
  final String message;
  @override
  String toString() => 'FixMatchException: $message';
}

class FixMatchService implements FixMatchRepository {
  FixMatchService({
    required this.providers,
    required this.art,
    required this.cache,
    this.loadOrder,
  });

  /// Every source this build ships, in built-in order.
  final List<MetadataProvider> providers;

  /// The user's saved order — read fresh, exactly as the scan does, so the two
  /// can never disagree about which source is preferred.
  final Future<List<SourcePreference>> Function()? loadOrder;
  final ArtCache art;
  final CacheDatabase cache;

  /// Ranked candidates for the user to pick from (the top result alone is
  /// unreliable — Stage 2 recon). Asks each configured source in order and
  /// returns the first that answers, so fix-match keeps working through an
  /// outage of the preferred one.
  @override
  Future<List<Series>> searchCandidates(String query) async {
    MetadataException? lastFailure;
    final load = loadOrder;
    final ordered = applySourceOrder(
      providers,
      (p) => p.token,
      load == null ? const [] : await load(),
      isFallbackOnly: (p) => p.isFallbackOnly,
    );
    for (final provider in ordered) {
      if (!await provider.isConfigured()) continue;
      try {
        return await provider.searchCandidates(query, perPage: 15);
      } on MetadataException catch (e) {
        lastFailure = e;
      }
    }
    // Surfaced in the fix-match pane as "Search failed: …" — the user is
    // actively waiting here, so silence would be worse than an error.
    throw lastFailure ??
        const MetadataException('No metadata source is configured.');
  }

  /// Assign (unmatched → match) or reassign a single file to [chosen].
  ///
  /// Identifies the file by STATTING it (it's a present file the user is
  /// correcting) for its content fingerprint — no path scheme, so this is
  /// unaffected by the relative-path/volume identity change and by moves.
  @override
  Future<void> assignFile({
    required String filePath,
    required Series chosen,
    int? anchoredEpisode,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {
    final stat = await _statOrNull(filePath);
    if (stat == null) {
      throw StateError('File not found (scan first): $filePath');
    }
    final modifiedAtMs = stat.modified.millisecondsSinceEpoch;
    final file = await cache.fileByFingerprint(stat.size, modifiedAtMs);
    if (file == null) {
      throw StateError('File not in cache (scan first): $filePath');
    }
    final seriesId = await _cacheSeries(chosen);
    await cache.upsertOverride(
      MatchOverrideRow(
        fileSize: stat.size,
        modifiedAtMs: modifiedAtMs,
        seriesId: seriesId,
        anchoredEpisode: anchoredEpisode ?? file.episodeNumber,
        continuousOffset: continuousOffset,
        displayContinuous: displayContinuous,
      ),
    );
  }

  /// Split: assign an ordered run of [filePaths] to [chosen], anchoring the
  /// first file at [anchorStart] within that entry and incrementing. The files
  /// do NOT move on disk — this is metadata only.
  ///
  /// [continuousOffset] is the REAL prior-season episode count (so continuous
  /// display = anchored + offset). The caller reads it from the prior season's
  /// cached episodeCount — never hardcoded.
  @override
  Future<void> assignRange({
    required List<String> filePaths,
    required Series chosen,
    int anchorStart = 1,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {
    final seriesId = await _cacheSeries(chosen);
    for (var i = 0; i < filePaths.length; i++) {
      final stat = await _statOrNull(filePaths[i]);
      if (stat == null) continue;
      await cache.upsertOverride(
        MatchOverrideRow(
          fileSize: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          seriesId: seriesId,
          anchoredEpisode: anchorStart + i,
          continuousOffset: continuousOffset,
          displayContinuous: displayContinuous,
        ),
      );
    }
  }

  /// Remove a file's override, reverting it to whatever the auto-matcher says.
  @override
  Future<void> clearOverride(String filePath) async {
    final stat = await _statOrNull(filePath);
    if (stat == null) return; // file gone -> nothing to key the delete on
    await cache.deleteOverride(stat.size, stat.modified.millisecondsSinceEpoch);
  }

  /// Stat [path], or null if it isn't a present file (so callers can guard).
  Future<FileStat?> _statOrNull(String path) async {
    if (!await File(path).exists()) return null;
    return File(path).stat();
  }

  /// Cache [s] under ITS LOCAL IDENTITY and return that id.
  ///
  /// `chosen.seriesId` is the provider's PROVISIONAL id — every provider stamps
  /// its own (Kitsu's, Jikan's, MAL's are all different numbers for the same
  /// show) and the scan path has always resolved it through `ensureSeriesId`
  /// before writing anything. This path used to call `ensureSeriesId` for its
  /// side effect and then write the provisional id anyway. Three things went
  /// wrong at once: a Kitsu id landed in the AniList-seeded band and was
  /// published as an AniList id; a show that already had a local identity got
  /// a SECOND series_cache row with its watch state stranded on the first; and
  /// the resulting external-id collision could surface as a raw UNIQUE
  /// constraint error on screen. Resolving first and writing the answer is the
  /// same rule the scan uses — one identity rule, not two.
  Future<int> _cacheSeries(Series s) async {
    if (s.externalIds.isEmpty) {
      throw const FixMatchException(
        'This entry carries no external id, so it cannot be given a local '
        'identity.',
      );
    }
    // ensureSeriesId recognises a show another provider already identified
    // (matching on ANY id the answer carries) and mints only when nothing
    // matches — and never re-points an id that belongs to a different series.
    final seriesId = await cache.ensureSeriesId(s.externalIds);
    final artPath = await art.ensureCover(seriesId, s.coverImageRef);
    await cache.upsertSeries(
      CachedSeriesRow(
        seriesId: seriesId,
        romaji: s.titles.romaji,
        english: s.titles.english,
        nativeTitle: s.titles.native,
        format: s.format,
        episodeCount: s.episodeCount,
        coverImageUrl: s.coverImageRef,
        coverImagePath: artPath,
      ),
    );
    return seriesId;
  }
}
