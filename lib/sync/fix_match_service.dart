import 'dart:io';

import '../data/metadata/metadata_provider.dart';
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
class FixMatchService implements FixMatchRepository {
  FixMatchService({
    required this.providers,
    required this.art,
    required this.cache,
  });

  /// Ordered metadata sources, same list and same priority as the scan uses.
  final List<MetadataProvider> providers;
  final ArtCache art;
  final CacheDatabase cache;

  /// Ranked candidates for the user to pick from (the top result alone is
  /// unreliable — Stage 2 recon). Asks each configured source in order and
  /// returns the first that answers, so fix-match keeps working through an
  /// outage of the preferred one.
  @override
  Future<List<Series>> searchCandidates(String query) async {
    MetadataException? lastFailure;
    for (final provider in providers) {
      if (!provider.isConfigured) continue;
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
    await _cacheSeries(chosen);
    await cache.upsertOverride(
      MatchOverrideRow(
        fileSize: stat.size,
        modifiedAtMs: modifiedAtMs,
        seriesId: chosen.seriesId,
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
    await _cacheSeries(chosen);
    for (var i = 0; i < filePaths.length; i++) {
      final stat = await _statOrNull(filePaths[i]);
      if (stat == null) continue;
      await cache.upsertOverride(
        MatchOverrideRow(
          fileSize: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          seriesId: chosen.seriesId,
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

  Future<void> _cacheSeries(Series s) async {
    // Learn every id the chosen entry carries. Without this a fix-matched show
    // got no MAL id and therefore no AniSkip data until some later refresh
    // happened to backfill it — the auto-matched path recorded ids, this one
    // silently did not.
    if (s.externalIds.isNotEmpty) {
      await cache.ensureSeriesId(s.externalIds);
    }
    final artPath = await art.ensureCover(s.seriesId, s.coverImageRef);
    await cache.upsertSeries(
      CachedSeriesRow(
        seriesId: s.seriesId,
        romaji: s.titles.romaji,
        english: s.titles.english,
        nativeTitle: s.titles.native,
        format: s.format,
        episodeCount: s.episodeCount,
        coverImageUrl: s.coverImageRef,
        coverImagePath: artPath,
      ),
    );
  }
}
