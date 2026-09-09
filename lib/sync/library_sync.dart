import 'dart:io';

import '../data/aniskip/aniskip_client.dart';
import '../data/cache/art_cache.dart';
import '../data/cache/cache_database.dart';
import '../data/cache/series_identity.dart';
import '../data/crossmap/cross_map_store.dart';
import '../data/metadata/metadata_provider.dart';
import '../data/folders/volume_resolver.dart';
import '../data/scanner/filename_parser.dart';
import '../data/scanner/folder_scanner.dart';
import '../data/scanner/series_matcher.dart';
import '../data/scanner/title_matching.dart';
import '../domain/models/external_ids.dart';
import '../domain/models/metadata_failure.dart';
import '../domain/models/refresh_summary.dart';
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
/// - Immediate population: a newly-seen, titled file is written as a PENDING
///   placeholder up front (phase 1, no network) and surfaced via [onDiscovered]
///   BEFORE identification runs — so the library shows it (named, blank art)
///   instantly, even offline. Identification (phase 2) then upgrades the row
///   in place: a match sets its seriesId; a genuine no-match flips it to
///   confirmed-unmatched; a transient lookup error LEAVES it pending (retried
///   next scan). A failed/absent AniList never drops a file — at worst it
///   stays a named placeholder.
class LibrarySync {
  LibrarySync({
    required this.scanner,
    required this.parser,
    required this.matcher,
    required this.cache,
    required this.art,
    required this.aniSkip,
    this.crossMap,
    VolumeResolver? resolver,
  }) : resolver = resolver ?? DiskutilVolumeResolver();

  final FolderScanner scanner;
  final FilenameParser parser;
  final SeriesMatcher matcher;
  final CacheDatabase cache;
  final ArtCache art;
  final AniSkipClient aniSkip;

  /// Cross-database id map, used ONLY to fill a MAL id AniList didn't give us
  /// (so AniSkip keeps working when AniList is unreachable). Optional: null —
  /// or a map that has never been fetched — leaves behaviour exactly as it was.
  final CrossMapStore? crossMap;

  /// Resolves a folder's CURRENT mount when its volume remounted under a new
  /// name (defaults to the macOS diskutil-backed resolver; injectable for tests).
  final VolumeResolver resolver;

  /// [onDiscovered] fires once, right after phase 1 has written the newly-seen
  /// files as pending placeholders (before any network). The UI wires it to a
  /// reload so the library paints placeholders immediately; identification then
  /// upgrades them on the same scan when AniList is reachable.
  Future<SyncSummary> sync(
    List<String> folderPaths, {
    void Function()? onDiscovered,
  }) async {
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
      for (final r in await cache.allSeriesRows()) r.seriesId: r,
    };

    // Map a known title -> its cached series, so a delta of an already-known
    // series never hits AniList.
    final knownTitleToId = <String, int>{};
    for (final r in cachedFiles.values) {
      if (r.seriesId != null && r.parsedTitle.isNotEmpty) {
        knownTitleToId.putIfAbsent(
          normalizeTitle(r.parsedTitle),
          () => r.seriesId!,
        );
      }
    }

    // Classify scanned files against the cache (by identity). A file is only
    // "unchanged" (skipped) when its bytes match AND it isn't a PENDING
    // placeholder — a pending row is unidentified, so it's re-attempted every
    // scan (this is how it auto-resolves once back online) even though the file
    // on disk hasn't changed. A confirmed-unmatched row (seriesId null,
    // pending false) is NOT retried — it stays put until fix-match, as before.
    final toIdentify = <(String, String)>[];
    var unchanged = 0;
    for (final key in scannedSet) {
      final c = cachedFiles[key];
      final s = stats[key]!;
      final bytesUnchanged =
          c != null &&
          c.fileSize == s.size &&
          c.modifiedAtMs == s.modified.millisecondsSinceEpoch;
      final isPending =
          c != null && c.seriesId == null && c.pendingIdentification;
      if (bytesUnchanged && !isPending) {
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

    // PHASE 1 (no network): write every NEWLY-SEEN, titled file as a pending
    // placeholder, then surface it. "New" = not already in the cache, so an
    // already-matched file whose bytes changed is NOT briefly demoted to a
    // placeholder — it keeps its match until phase 2 re-resolves it. Files with
    // no parseable title are left for phase 2 (they become confirmed-unmatched;
    // re-scanning can't help a name the parser can't read). Phase 2's upserts
    // overwrite these rows in place (a match clears the pending flag); rows
    // whose lookup later errors simply remain as the pending placeholders
    // written here.
    final pendingPlaceholders = [
      for (final key in toIdentify)
        if (cachedFiles[key] == null && parsed[key]!.title.isNotEmpty)
          () {
            final pf = parsed[key]!;
            final s = stats[key]!;
            return CachedFileRow(
              folderPath: key.$1,
              relativePath: key.$2,
              fileSize: s.size,
              modifiedAtMs: s.modified.millisecondsSinceEpoch,
              seriesId: null,
              episodeNumber: pf.episodeNumber,
              parsedTitle: pf.title,
              matchScore: 0,
              releaseGroup: pf.releaseGroup,
              pendingIdentification: true,
            );
          }(),
    ];
    if (pendingPlaceholders.isNotEmpty) {
      await cache.upsertFiles(pendingPlaceholders);
    }
    onDiscovered?.call();

    // PHASE 2 (network): resolve each distinct delta title — reuse a cached
    // series, or search.
    final resolved = <String, _Resolved>{};
    final erroredTitles = <String>{};
    var anilistLookups = 0;
    MetadataFailure? apiFailure;
    for (final entry in deltaTitles.entries) {
      final norm = entry.key;
      final sample = entry.value;
      final knownId = knownTitleToId[norm];
      if (knownId != null) {
        final row = cachedSeries[knownId];
        final score = row == null
            ? 1.0
            : rankCandidates(sample, [_seriesFromRow(row)]).score;
        resolved[norm] = _Resolved(seriesId: knownId, score: score);
        continue;
      }
      try {
        anilistLookups++;
        final result = await matcher.match(sample);
        final found = result.series;
        // Identity is OURS, not the provider's. ensureSeriesId recognises a
        // show another provider already identified (matching on ANY id the
        // answer carries) and mints only when nothing matches — without this
        // the same show would fork under two ids and strand watch progress.
        final seriesId = found == null
            ? null
            : await cache.ensureSeriesId(found.externalIds);
        resolved[norm] = _Resolved(
          seriesId: seriesId,
          score: result.score,
          freshSeries: found,
        );
      } on MetadataException catch (e) {
        erroredTitles.add(norm); // transient — skip, retry next scan
        // First cause wins: an outage fails every lookup the same way, and the
        // first is the one that isn't a knock-on effect of a degrading API.
        apiFailure ??= e.failure;
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
    // Only report a cause when EVERY lookup failed; a lone failure among
    // successes isn't an outage and must not accuse the user's connection.
    final reportedFailure = apiUnreachable ? apiFailure : null;
    final effectiveRemovedKeys = apiUnreachable
        ? const <(String, String)>[]
        : removedKeys;

    // Download art only for newly-fetched series (incremental).
    final seriesUpserts = <CachedSeriesRow>[];
    for (final r in resolved.values) {
      final fresh = r.freshSeries;
      final seriesId = r.seriesId;
      if (fresh == null || seriesId == null) continue;
      // Art is filed under OUR id, not the provider's — they diverge as soon as
      // a show is identified by a source other than AniList.
      final artPath = await art.ensureCover(seriesId, fresh.coverImageRef);
      seriesUpserts.add(_seriesRow(fresh, artPath, seriesId));
    }

    // Build the final (identified) file rows. A file whose title errored this
    // scan is NOT written here, so it KEEPS whatever it already is — a new file
    // stays the pending placeholder from phase 1 (retried next scan), an
    // already-matched changed file keeps its match. Everything else is written
    // with pendingIdentification=false: a match (seriesId set) or a genuine
    // no-match (seriesId null = confirmed-unmatched, the fix-match screen).
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
      final seriesId = res?.seriesId;
      final s = stats[key]!;
      fileUpserts.add(
        CachedFileRow(
          folderPath: key.$1,
          relativePath: key.$2,
          fileSize: s.size,
          modifiedAtMs: s.modified.millisecondsSinceEpoch,
          seriesId: seriesId,
          episodeNumber: pf.episodeNumber,
          parsedTitle: pf.title,
          matchScore: res?.score ?? 0,
          releaseGroup: pf.releaseGroup,
          pendingIdentification: false,
        ),
      );
      if (seriesId != null) {
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
      for (final e in (await cache.externalIdsBySeriesId()).entries)
        e.key: e.value.mal,
    };
    for (final r in resolved.values) {
      final fresh = r.freshSeries;
      final seriesId = r.seriesId;
      if (fresh != null && seriesId != null) {
        idMalById[seriesId] = fresh.externalIds.mal;
      }
    }
    final skipKeys = <(int, int)>{
      for (final f in fileUpserts)
        if (f.seriesId != null && f.episodeNumber != null)
          (f.seriesId!, f.episodeNumber!),
    };
    final malIds = await _resolveMalIds(idMalById, skipKeys.map((k) => k.$1));
    final skipUpserts = <SkipSegmentRow>[];
    for (final (seriesId, episode) in skipKeys) {
      final mal = malIds[seriesId];
      if (mal == null) continue;
      try {
        final skips = await aniSkip.fetchSkips(mal, episode);
        if (skips == null) continue; // no data -> no row (graceful)
        skipUpserts.add(
          SkipSegmentRow(
            seriesId: seriesId,
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

    // For every title that resolved to a real AniList id this scan, carry any
    // watch progress recorded while it was a pending placeholder over to the
    // real id (rekeyed atomically in applySync). The placeholder id is the same
    // pure function the read path uses, so the keys line up; this is a no-op
    // for titles that never had a placeholder watched.
    final promotions = <(int, int)>[
      for (final entry in resolved.entries)
        if (entry.value.seriesId != null)
          (placeholderSeriesId(entry.key), entry.value.seriesId!),
    ];

    await cache.applySync(
      seriesUpserts: seriesUpserts,
      fileUpserts: fileUpserts,
      removedKeys: effectiveRemovedKeys,
      skipUpserts: skipUpserts,
      promotions: promotions,
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
      apiFailure: reportedFailure,
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
  Future<RefreshSummary> refreshMetadata() async {
    final files = await cache.allFileRows();
    final overrides = {
      for (final o in await cache.allOverrideRows())
        (o.fileSize, o.modifiedAtMs): o,
    };

    // Every AniList entry the library references (auto-matched files + overrides).
    final ids = <int>{
      for (final f in files)
        if (f.seriesId != null) f.seriesId!,
      for (final o in overrides.values) o.seriesId,
    };

    // Re-fetch and upsert (no prune).
    // Seeded from the CACHE first: a refresh whose fetch fails still knows the
    // MAL ids it already stored, so skips can still be backfilled offline
    // (before this, an unreachable source left the map empty and no skip was
    // ever fetched, even for shows whose idMal was already known).
    final idMalById = <int, int?>{
      for (final e in (await cache.externalIdsBySeriesId()).entries)
        e.key: e.value.mal,
    };
    // Each provider is re-asked BY ITS OWN ids, which is why the side table
    // exists: our series_id means nothing to Kitsu or MAL.
    final externalIds = await cache.externalIdsBySeriesId();
    // Previous cover per series, so a source switch actually replaces the art
    // instead of keeping the first source's picture forever.
    final cachedSeriesRows = {
      for (final r in await cache.allSeriesRows()) r.seriesId: r,
    };
    var seriesRefreshed = 0;
    MetadataFailure? failure;

    for (final provider in await matcher.activeProviders()) {
      if (!provider.isConfigured) continue;

      // series_id <-> this provider's id, for the ids we actually hold.
      final providerIdBySeries = <int, int>{};
      for (final seriesId in ids) {
        final providerId = externalIds[seriesId]?.forProvider(provider.token);
        if (providerId != null) providerIdBySeries[seriesId] = providerId;
      }
      if (providerIdBySeries.isEmpty) continue;
      final seriesByProviderId = {
        for (final e in providerIdBySeries.entries) e.value: e.key,
      };

      try {
        final fetched = await provider.fetchByProviderIds(
          providerIdBySeries.values.toList(),
        );
        for (final fresh in fetched) {
          // Map the provider's answer back onto OUR identity — never adopt the
          // provider's id as the key.
          final providerId = fresh.externalIds.forProvider(provider.token);
          final seriesId = seriesByProviderId[providerId];
          // Answered about something we didn't ask for.
          if (seriesId == null) continue;
          // A null field here CANNOT blank a cached value: upsertSeries goes
          // through drift's insertOnConflictUpdate, whose DO UPDATE SET omits
          // null columns (toColumns(nullToAbsent: true)). So a degraded payload,
          // or a cover download that failed, leaves the existing row's fields
          // intact — the no-wipe guarantee this method promises. Pinned by
          // test/metadata_refresh_failure_test.dart.
          final prior = cachedSeriesRows[seriesId];
          final artPath = await art.ensureCover(
            seriesId,
            fresh.coverImageRef,
            cachedUrl: prior?.coverImageUrl,
            cachedPath: prior?.coverImagePath,
          );
          await cache.upsertSeries(_seriesRow(fresh, artPath, seriesId));
          // Learn any ids this answer carried that we didn't have.
          await cache.ensureSeriesId(
            fresh.externalIds.fillFrom(
              externalIds[seriesId] ?? ExternalIds.empty,
            ),
          );
          idMalById[seriesId] = fresh.externalIds.mal ?? idMalById[seriesId];
          seriesRefreshed++;
        }
        failure = null;
        break; // the preferred source answered; lower ones are the fallback
      } on MetadataException catch (e) {
        // Transient — keep existing metadata and try the next source. Reported
        // rather than swallowed: a silent catch here made an outage look like a
        // successful "Refreshed 0 series".
        failure = e.failure;
      }
    }

    // Effective (seriesId, anchored) per matched file — overrides win, so
    // fix-matched episodes get skips keyed to their corrected identity.
    final identities = <(int, int)>{};
    for (final f in files) {
      final o = overrides[(f.fileSize, f.modifiedAtMs)];
      if (o != null) {
        identities.add((o.seriesId, o.anchoredEpisode ?? 0));
      } else if (f.seriesId != null) {
        identities.add((f.seriesId!, f.episodeNumber ?? 0));
      }
    }

    // Fetch AniSkip only for identities missing a cached skip row.
    final haveSkips = {
      for (final s in await cache.allSkipRows()) (s.seriesId, s.episode),
    };
    final malIds = await _resolveMalIds(idMalById, identities.map((i) => i.$1));
    var skipsFetched = 0;
    for (final (seriesId, episode) in identities) {
      if (haveSkips.contains((seriesId, episode))) continue;
      final mal = malIds[seriesId];
      if (mal == null) continue;
      try {
        final skips = await aniSkip.fetchSkips(mal, episode);
        if (skips == null) continue;
        await cache.upsertSkipSegment(
          SkipSegmentRow(
            seriesId: seriesId,
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

    return RefreshSummary(
      seriesRefreshed: seriesRefreshed,
      skipsFetched: skipsFetched,
      failure: failure,
    );
  }

  /// MAL ids for [seriesIds]: whatever a provider already gave us, with the
  /// gaps filled from the cross-map.
  ///
  /// This is what makes AniSkip independent of AniList. `idMal` used to come
  /// ONLY from AniList's response, so a show identified while AniList was
  /// unreachable had no MAL id and silently lost auto-skip forever. The map
  /// supplies it offline. A null [crossMap], an unfetched map, or an id the map
  /// doesn't know all leave the entry exactly as it was — never worse than
  /// before. Placeholder ids are negative and simply miss.
  Future<Map<int, int?>> _resolveMalIds(
    Map<int, int?> known,
    Iterable<int> seriesIds,
  ) async {
    final store = crossMap;
    if (store == null) return known;
    final missing = {
      for (final id in seriesIds)
        if (known[id] == null) id,
    };
    if (missing.isEmpty) return known; // nothing to look up -> no map load
    final map = await store.load();
    if (map.isEmpty) return known;
    final resolved = Map<int, int?>.of(known);
    for (final id in missing) {
      final mal = map.malFor(id);
      if (mal != null) resolved[id] = mal;
    }
    return resolved;
  }

  /// [seriesId] overrides the provider's own id: the provider reports what IT
  /// calls the show, but the cache is keyed by our surrogate.
  CachedSeriesRow _seriesRow(Series s, String? artPath, [int? seriesId]) =>
      CachedSeriesRow(
        seriesId: seriesId ?? s.seriesId,
        romaji: s.titles.romaji,
        english: s.titles.english,
        nativeTitle: s.titles.native,
        format: s.format,
        episodeCount: s.episodeCount,
        coverImageUrl: s.coverImageRef,
        coverImagePath: artPath,
      );

  Series _seriesFromRow(CachedSeriesRow r) => Series(
    seriesId: r.seriesId,
    titles: Titles(romaji: r.romaji, english: r.english, native: r.nativeTitle),
  );

  String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }
}

/// Per-title resolution result during a sync.
class _Resolved {
  _Resolved({required this.seriesId, required this.score, this.freshSeries});

  final int? seriesId;
  final double score;

  /// Non-null only when freshly fetched from AniList (needs caching + art).
  final Series? freshSeries;
}
