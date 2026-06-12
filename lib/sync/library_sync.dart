import 'dart:io';

import '../data/anilist/anilist_client.dart';
import '../data/aniskip/aniskip_client.dart';
import '../data/cache/art_cache.dart';
import '../data/cache/cache_database.dart';
import '../data/folders/volume_resolver.dart';
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
    required this.aniSkip,
    VolumeResolver? resolver,
  }) : resolver = resolver ?? DiskutilVolumeResolver();

  final FolderScanner scanner;
  final FilenameParser parser;
  final SeriesMatcher matcher;
  final CacheDatabase cache;
  final ArtCache art;
  final AniSkipClient aniSkip;

  /// Resolves a folder's CURRENT mount when its volume remounted under a new
  /// name (defaults to the macOS diskutil-backed resolver; injectable for tests).
  final VolumeResolver resolver;

  Future<SyncSummary> sync(List<String> folderPaths) async {
    // Folder rows carry each folder's volume binding (UUID + subpath); used to
    // FOLLOW a volume that remounted under a different /Volumes name, and to
    // BACKFILL the binding the first time we resolve an unbound /Volumes folder.
    final folderRows = {for (final r in await cache.allFolderRows()) r.path: r};

    // Scan each folder independently, keyed by IDENTITY (folderPath = the
    // folder's stable identity from [folderPaths]; relativePath = the file's
    // path within it) — NOT an absolute mount path. So a remount under a new
    // mount name doesn't change any key. A folder whose volume isn't mounted
    // (or that we can't read) is surfaced and its cached files are PRESERVED.
    final stats = <(String folderPath, String relativePath), FileStat>{};
    final unreadableFolders = <String>{}; // stable folder identities
    for (final folderPath in folderPaths) {
      final row = folderRows[folderPath];
      final current = await resolveFolderPath(
        storedPath: folderPath,
        volumeId: row?.volumeId,
        volumeSubpath: row?.volumeSubpath,
        resolver: resolver,
      );
      if (current == null) {
        unreadableFolders.add(folderPath); // volume not mounted -> missing
        continue;
      }
      // Backfill the volume UUID once we can resolve an as-yet-unbound folder
      // (migrated folders + freshly added ones). The resolver returns null for
      // internal-disk paths, so only removable/network volumes get bound — they
      // are the ones whose mount name can change. Best-effort.
      if (row != null && row.volumeId == null) {
        final info = await resolver.infoForPath(current);
        if (info != null) {
          await cache.bindFolderVolume(
            folderPath,
            info.volumeId,
            volumeSubpathOf(current, info.mountPoint),
          );
        }
      }
      try {
        for (final abs in await scanner.findVideoFiles(current)) {
          final relative = abs.length > current.length
              ? abs.substring(current.length + 1)
              : abs;
          stats[(folderPath, relative)] = await File(abs).stat();
        }
      } on FileSystemException {
        unreadableFolders.add(folderPath);
      }
    }
    final scannedSet = stats.keys.toSet();

    final cachedFiles = {
      for (final r in await cache.allFileRows())
        (r.folderPath, r.relativePath): r,
    };
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

    // Classify scanned files against the cache (by identity).
    final toIdentify = <(String, String)>[];
    var unchanged = 0;
    for (final key in scannedSet) {
      final c = cachedFiles[key];
      final s = stats[key]!;
      if (c != null &&
          c.fileSize == s.size &&
          c.modifiedAtMs == s.modified.millisecondsSinceEpoch) {
        unchanged++;
      } else {
        toIdentify.add(key);
      }
    }
    // Removed = cached files not found this scan, EXCEPT those under a folder
    // we couldn't read/resolve (preserve those — access lapsed or volume
    // unplugged, not deleted).
    final removedKeys = [
      for (final key in cachedFiles.keys)
        if (!scannedSet.contains(key) && !unreadableFolders.contains(key.$1))
          key,
    ];

    // Parse the deltas and collect distinct titles (parse the file's basename,
    // the last segment of its relative path).
    final parsed = {
      for (final key in toIdentify) key: parser.parse(_basename(key.$2)),
    };
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

    // RESILIENCE: if every lookup we attempted failed (403 / transport /
    // timeout), AniList is unreachable — NOT "the content is gone". Treat it
    // like an unreadable folder and PRESERVE the cache: skip all removals (which
    // also makes the prune a no-op, since every cached series keeps its files).
    // A transient API outage must never empty a populated library; the next
    // healthy scan reconciles real moves/deletions.
    final apiUnreachable =
        anilistLookups > 0 && erroredTitles.length == anilistLookups;
    final effectiveRemovedKeys = apiUnreachable
        ? const <(String, String)>[]
        : removedKeys;

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
    for (final key in toIdentify) {
      final pf = parsed[key]!;
      final norm = pf.title.isEmpty ? null : normalizeTitle(pf.title);
      if (norm != null && erroredTitles.contains(norm)) {
        errored++;
        continue;
      }
      final res = norm == null ? null : resolved[norm];
      final anilistId = res?.anilistId;
      final s = stats[key]!;
      fileUpserts.add(
        CachedFileRow(
          folderPath: key.$1,
          relativePath: key.$2,
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

    // Fetch OP/ED skip windows for the delta episodes (online, scan-time only).
    // idMal comes from the freshly-fetched series or the cached row. One fetch
    // per distinct (entry, episode) — deduped across multi-source files, and
    // already incremental (fileUpserts are only the deltas). Failures/no-data
    // are skipped silently; partial AniSkip coverage is normal.
    final idMalById = <int, int?>{
      for (final r in cachedSeries.values) r.anilistId: r.idMal,
    };
    for (final r in resolved.values) {
      final fresh = r.freshSeries;
      if (fresh != null) idMalById[fresh.anilistId] = fresh.idMal;
    }
    final skipKeys = <(int, int)>{
      for (final f in fileUpserts)
        if (f.anilistId != null && f.episodeNumber != null)
          (f.anilistId!, f.episodeNumber!),
    };
    final skipUpserts = <SkipSegmentRow>[];
    for (final (anilistId, episode) in skipKeys) {
      final mal = idMalById[anilistId];
      if (mal == null) continue;
      try {
        final skips = await aniSkip.fetchSkips(mal, episode);
        if (skips == null) continue; // no data -> no row (graceful)
        skipUpserts.add(
          SkipSegmentRow(
            anilistId: anilistId,
            episode: episode,
            introStartMs: skips.intro?.start.inMilliseconds,
            introEndMs: skips.intro?.end.inMilliseconds,
            outroStartMs: skips.outro?.start.inMilliseconds,
            outroEndMs: skips.outro?.end.inMilliseconds,
          ),
        );
      } on AniSkipException {
        // Transient — leave this episode without skip data (no scan failure).
      }
    }

    await cache.applySync(
      seriesUpserts: seriesUpserts,
      fileUpserts: fileUpserts,
      removedKeys: effectiveRemovedKeys,
      skipUpserts: skipUpserts,
    );

    return SyncSummary(
      filesScanned: scannedSet.length,
      unchanged: unchanged,
      processed: matched + unmatched,
      removed: effectiveRemovedKeys.length,
      matched: matched,
      unmatched: unmatched,
      errored: errored,
      anilistLookups: anilistLookups,
      unreadableFolders: unreadableFolders.toList(),
      apiUnreachable: apiUnreachable,
    );
  }

  /// Re-fetch metadata for ALREADY-cached series (the "refresh metadata"
  /// backfill) WITHOUT scanning files or pruning anything — fix-matches,
  /// watch-state, and file matches are untouched. Re-fetches each referenced
  /// entry by AniList id to pick up fields added later (notably `idMal`), then
  /// fetches AniSkip for episode identities that don't yet have a cached skip
  /// row. Idempotent and rate-friendly: already-cached skips aren't re-fetched.
  ///
  /// Online action; the cache stays the offline read path. Returns counts for
  /// a confirmation message.
  Future<({int seriesRefreshed, int skipsFetched})> refreshMetadata() async {
    final files = await cache.allFileRows();
    final overrides = {
      for (final o in await cache.allOverrideRows())
        (o.fileSize, o.modifiedAtMs): o,
    };

    // Every AniList entry the library references (auto-matched files + overrides).
    final ids = <int>{
      for (final f in files)
        if (f.anilistId != null) f.anilistId!,
      for (final o in overrides.values) o.anilistId,
    };

    // Re-fetch by id and upsert (no prune). idMal becomes available here.
    final idMalById = <int, int?>{};
    var seriesRefreshed = 0;
    try {
      for (final s in await matcher.anilist.fetchSeriesByIds(ids.toList())) {
        final artPath = await art.ensureCover(s.anilistId, s.coverImageRef);
        await cache.upsertSeries(_seriesRow(s, artPath));
        idMalById[s.anilistId] = s.idMal;
        seriesRefreshed++;
      }
    } on AniListException {
      // Transient — keep existing metadata; a later refresh retries.
    }

    // Effective (anilistId, anchored) per matched file — overrides win, so
    // fix-matched episodes get skips keyed to their corrected identity.
    final identities = <(int, int)>{};
    for (final f in files) {
      final o = overrides[(f.fileSize, f.modifiedAtMs)];
      if (o != null) {
        identities.add((o.anilistId, o.anchoredEpisode ?? 0));
      } else if (f.anilistId != null) {
        identities.add((f.anilistId!, f.episodeNumber ?? 0));
      }
    }

    // Fetch AniSkip only for identities missing a cached skip row.
    final haveSkips = {
      for (final s in await cache.allSkipRows()) (s.anilistId, s.episode),
    };
    var skipsFetched = 0;
    for (final (anilistId, episode) in identities) {
      if (haveSkips.contains((anilistId, episode))) continue;
      final mal = idMalById[anilistId];
      if (mal == null) continue;
      try {
        final skips = await aniSkip.fetchSkips(mal, episode);
        if (skips == null) continue;
        await cache.upsertSkipSegment(
          SkipSegmentRow(
            anilistId: anilistId,
            episode: episode,
            introStartMs: skips.intro?.start.inMilliseconds,
            introEndMs: skips.intro?.end.inMilliseconds,
            outroStartMs: skips.outro?.start.inMilliseconds,
            outroEndMs: skips.outro?.end.inMilliseconds,
          ),
        );
        skipsFetched++;
      } on AniSkipException {
        // Transient — leave this episode for a later refresh.
      }
    }

    return (seriesRefreshed: seriesRefreshed, skipsFetched: skipsFetched);
  }

  CachedSeriesRow _seriesRow(Series s, String? artPath) => CachedSeriesRow(
    anilistId: s.anilistId,
    idMal: s.idMal,
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
