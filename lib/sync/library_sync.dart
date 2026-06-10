import 'dart:io';

import '../data/anilist/anilist_client.dart';
import '../data/cache/art_cache.dart';
import '../data/cache/cache_database.dart';
import '../data/scanner/filename_parser.dart';
import '../data/scanner/folder_scanner.dart';
import '../data/scanner/series_matcher.dart';
import '../data/scanner/title_matching.dart';
import '../domain/models/series.dart';
import '../domain/models/sync_summary.dart';
import '../domain/models/titles.dart';

/// The fill path: scan a folder, identify only the deltas, and write the cache.
/// Runs on scan/refresh only — never on a UI read.
///
/// Invariants:
/// - Incremental: a file unchanged by (path, size, mtime) is skipped entirely.
/// - Never refetch unchanged: a delta whose title already maps to a cached
///   series reuses it (no AniList call).
/// - Partial-failure safe: a transient AniList error skips those files (not
///   cached → retried next scan); a genuine no-match is recorded (null
///   anilistId) and persists across rescans. The write is one transaction.
class LibrarySync {
  LibrarySync({
    required this.scanner,
    required this.parser,
    required this.matcher,
    required this.cache,
    required this.art,
  });

  final FolderScanner scanner;
  final FilenameParser parser;
  final SeriesMatcher matcher;
  final CacheDatabase cache;
  final ArtCache art;

  Future<SyncSummary> sync(List<String> folderPaths) async {
    // Scan each folder independently. A folder we can't read (access lapsed or
    // moved) is surfaced loudly and its cached files are PRESERVED — never
    // treated as removed (no silent data loss).
    final stats = <String, FileStat>{};
    final unreadableFolders = <String>[];
    for (final folder in folderPaths) {
      try {
        for (final p in await scanner.findVideoFiles(folder)) {
          stats[p] = await File(p).stat();
        }
      } on FileSystemException {
        unreadableFolders.add(folder);
      }
    }
    final scannedSet = stats.keys.toSet();

    final cachedFiles = {for (final r in await cache.allFileRows()) r.path: r};
    final cachedSeries = {
      for (final r in await cache.allSeriesRows()) r.anilistId: r,
    };

    // Map a known title -> its cached series, so a delta of an already-known
    // series never hits AniList.
    final knownTitleToId = <String, int>{};
    for (final r in cachedFiles.values) {
      if (r.anilistId != null && r.parsedTitle.isNotEmpty) {
        knownTitleToId.putIfAbsent(
          normalizeTitle(r.parsedTitle),
          () => r.anilistId!,
        );
      }
    }

    // Classify scanned files against the cache.
    final toIdentify = <String>[];
    var unchanged = 0;
    for (final p in scannedSet) {
      final c = cachedFiles[p];
      final s = stats[p]!;
      if (c != null &&
          c.fileSize == s.size &&
          c.modifiedAtMs == s.modified.millisecondsSinceEpoch) {
        unchanged++;
      } else {
        toIdentify.add(p);
      }
    }
    // Removed = cached files not found this scan, EXCEPT those under a folder
    // we couldn't read (preserve those — access lapsed, not deleted).
    final removedPaths = [
      for (final p in cachedFiles.keys)
        if (!scannedSet.contains(p) && !_underAnyFolder(p, unreadableFolders))
          p,
    ];

    // Parse the deltas and collect distinct titles.
    final parsed = {for (final p in toIdentify) p: parser.parse(_basename(p))};
    final deltaTitles = <String, String>{};
    for (final pf in parsed.values) {
      if (pf.title.isNotEmpty) {
        deltaTitles.putIfAbsent(normalizeTitle(pf.title), () => pf.title);
      }
    }

    // Resolve each distinct delta title: reuse a cached series, or search.
    final resolved = <String, _Resolved>{};
    final erroredTitles = <String>{};
    var anilistLookups = 0;
    for (final entry in deltaTitles.entries) {
      final norm = entry.key;
      final sample = entry.value;
      final knownId = knownTitleToId[norm];
      if (knownId != null) {
        final row = cachedSeries[knownId];
        final score = row == null
            ? 1.0
            : rankCandidates(sample, [_seriesFromRow(row)]).score;
        resolved[norm] = _Resolved(anilistId: knownId, score: score);
        continue;
      }
      try {
        anilistLookups++;
        final result = await matcher.match(sample);
        resolved[norm] = _Resolved(
          anilistId: result.series?.anilistId,
          score: result.score,
          freshSeries: result.series,
        );
      } on AniListException {
        erroredTitles.add(norm); // transient — skip, retry next scan
      }
    }

    // Download art only for newly-fetched series (incremental).
    final seriesUpserts = <CachedSeriesRow>[];
    for (final r in resolved.values) {
      final fresh = r.freshSeries;
      if (fresh == null) continue;
      final artPath = await art.ensureCover(
        fresh.anilistId,
        fresh.coverImageRef,
      );
      seriesUpserts.add(_seriesRow(fresh, artPath));
    }

    // Build file rows, skipping files whose title errored.
    final fileUpserts = <CachedFileRow>[];
    var matched = 0;
    var unmatched = 0;
    var errored = 0;
    for (final p in toIdentify) {
      final pf = parsed[p]!;
      final norm = pf.title.isEmpty ? null : normalizeTitle(pf.title);
      if (norm != null && erroredTitles.contains(norm)) {
        errored++;
        continue;
      }
      final res = norm == null ? null : resolved[norm];
      final anilistId = res?.anilistId;
      final s = stats[p]!;
      fileUpserts.add(
        CachedFileRow(
          path: p,
          fileSize: s.size,
          modifiedAtMs: s.modified.millisecondsSinceEpoch,
          anilistId: anilistId,
          episodeNumber: pf.episodeNumber,
          parsedTitle: pf.title,
          matchScore: res?.score ?? 0,
          releaseGroup: pf.releaseGroup,
        ),
      );
      if (anilistId != null) {
        matched++;
      } else {
        unmatched++;
      }
    }

    await cache.applySync(
      seriesUpserts: seriesUpserts,
      fileUpserts: fileUpserts,
      removedPaths: removedPaths,
    );

    return SyncSummary(
      filesScanned: scannedSet.length,
      unchanged: unchanged,
      processed: matched + unmatched,
      removed: removedPaths.length,
      matched: matched,
      unmatched: unmatched,
      errored: errored,
      anilistLookups: anilistLookups,
      unreadableFolders: unreadableFolders,
    );
  }

  bool _underAnyFolder(String filePath, List<String> folders) {
    for (final f in folders) {
      if (filePath == f || filePath.startsWith('$f/')) return true;
    }
    return false;
  }

  CachedSeriesRow _seriesRow(Series s, String? artPath) => CachedSeriesRow(
    anilistId: s.anilistId,
    romaji: s.titles.romaji,
    english: s.titles.english,
    nativeTitle: s.titles.native,
    format: s.format,
    episodeCount: s.episodeCount,
    coverImageUrl: s.coverImageRef,
    coverImagePath: artPath,
  );

  Series _seriesFromRow(CachedSeriesRow r) => Series(
    anilistId: r.anilistId,
    titles: Titles(romaji: r.romaji, english: r.english, native: r.nativeTitle),
  );

  String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }
}

/// Per-title resolution result during a sync.
class _Resolved {
  _Resolved({required this.anilistId, required this.score, this.freshSeries});

  final int? anilistId;
  final double score;

  /// Non-null only when freshly fetched from AniList (needs caching + art).
  final Series? freshSeries;
}
