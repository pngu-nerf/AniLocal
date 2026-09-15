import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../data/cache/art_cache.dart';
import '../data/cache/cache_database.dart';
import '../data/cache/series_identity.dart';
import '../data/crossmap/cross_map_store.dart';
import '../data/folders/volume_resolver.dart';
import '../data/metadata/metadata_provider.dart';
import '../data/paths.dart';
import '../data/scanner/filename_parser.dart';
import '../data/scanner/folder_scanner.dart';
import '../data/scanner/series_matcher.dart';
import '../data/scanner/title_matching.dart';
import '../data/skip/skip_provider.dart';
import '../diagnostics/app_log.dart';
import '../domain/models/external_ids.dart';
import '../domain/models/metadata_failure.dart';
import '../domain/models/refresh_summary.dart';
import '../domain/models/series.dart';
import '../domain/models/skip_range.dart';
import '../domain/models/source_preference.dart';
import '../domain/models/sync_control.dart';
import '../domain/models/sync_summary.dart';
import '../domain/models/titles.dart';
import 'source_health.dart';

/// A file's identity in the cache: the owning folder's STABLE identity (the
/// path it was added under) plus the file's path within it. Never an absolute
/// mount path, so a volume that remounts under another name changes no key.
typedef FileKey = (String folderPath, String relativePath);

/// An episode's identity: our series id plus the anchored episode number.
typedef EpisodeKey = (int seriesId, int episode);

/// The fill path: scan a folder, identify only the deltas, and write the cache.
/// Runs on scan/refresh only — never on a UI read.
///
/// Invariants:
/// - Incremental: a file unchanged by (path, size, mtime) is skipped entirely.
/// - Never refetch unchanged: a delta whose title already maps to a cached
///   series reuses it (no metadata lookup).
/// - Immediate population: a newly-seen, titled file is written as a PENDING
///   placeholder up front (phase 1, no network) and surfaced via `sync`'s
///   `onDiscovered` BEFORE identification runs — so the library shows it
///   (named, blank art) instantly, even offline. Identification (phase 2) then
///   upgrades the row in place: a match sets its seriesId; a genuine no-match
///   flips it to confirmed-unmatched; a transient lookup error LEAVES it
///   pending (retried next scan). A failed/absent metadata source never drops
///   a file — at worst it stays a named placeholder.
/// - Committed in batches: phase 2 identifies [batchSize] titles at a time and
///   writes each batch before starting the next, so a quit, a crash or a
///   cancel twenty minutes into a first scan keeps what was done. Removals
///   are applied last, only by a run that finished and saw every source
///   answer.
/// - One run at a time: this is the cache's only writer and is not reentrant
///   ([SyncAlreadyRunning] if a second run is started).
///
/// The method bodies are short; the work lives in the private phase methods
/// below, each of which is a pure function of its inputs plus the cache, so
/// the two entry points share the pieces they have in common (resolving
/// mounts, asking skip sources) instead of carrying two copies.
class LibrarySync {
  LibrarySync({
    required this.scanner,
    required this.parser,
    required this.matcher,
    required this.cache,
    required this.art,
    required this.skipProviders,
    this.loadSkipOrder,
    this.crossMap,
    VolumeResolver? resolver,
    this.batchSize = 25,
  }) : resolver = resolver ?? DiskutilVolumeResolver();

  final FolderScanner scanner;
  final FilenameParser parser;
  final SeriesMatcher matcher;
  final CacheDatabase cache;
  final ArtCache art;

  /// Ordered skip sources, same shape as the metadata chain: the first
  /// configured, enabled one that HAS data for an episode wins. A source with
  /// no data is not a failure — partial coverage is normal here.
  final List<SkipProvider> skipProviders;

  /// The user's saved skip-source order, read fresh so reordering takes effect
  /// without a restart. Null = use [skipProviders] as given.
  final Future<List<SourcePreference>> Function()? loadSkipOrder;

  /// Cross-database id map, used ONLY to fill a MAL id the metadata source did
  /// not supply (so AniSkip keeps working when it is unreachable). Optional:
  /// null — or a map that has never been fetched — leaves behaviour exactly as
  /// it was.
  final CrossMapStore? crossMap;

  /// Resolves a folder's CURRENT mount when its volume remounted under a new
  /// name (defaults to the macOS diskutil-backed resolver; injectable for tests).
  final VolumeResolver resolver;

  /// Distinct titles identified and committed per batch during a scan.
  final int batchSize;

  bool _running = false;

  /// Whether a scan or refresh is in flight. The UI reads this to disable its
  /// controls; the guard itself is [_exclusive].
  bool get isRunning => _running;

  /// Scan [folderPaths] and reconcile the cache with what is on disk.
  ///
  /// [onDiscovered] fires once, right after phase 1 has written the newly-seen
  /// files as pending placeholders (before any network). The UI wires it to a
  /// reload so the library paints placeholders immediately; identification then
  /// upgrades them on the same scan when a metadata source is reachable.
  /// [onProgress] fires after each committed batch. [cancellation] stops the
  /// run at the next checkpoint; the summary then says `cancelled`.
  Future<SyncSummary> sync(
    List<String> folderPaths, {
    void Function()? onDiscovered,
    void Function(SyncProgress progress)? onProgress,
    SyncCancellation? cancellation,
  }) => _exclusive(
    () => _sync(
      folderPaths,
      onDiscovered: onDiscovered,
      onProgress: onProgress,
      cancellation: cancellation ?? SyncCancellation(),
    ),
  );

  /// Re-fetch metadata for ALREADY-cached series (the "refresh metadata"
  /// backfill) WITHOUT scanning files or pruning anything — fix-matches,
  /// watch-state, and file matches are untouched. Re-fetches each referenced
  /// entry by each provider's own ids to pick up fields added later, then asks
  /// every enabled skip source for episode identities that don't yet have a
  /// row. Idempotent and rate-friendly: already-answered skips aren't re-asked.
  ///
  /// Online action; the cache stays the offline read path. Returns counts for
  /// a confirmation message.
  Future<RefreshSummary> refreshMetadata({
    void Function(SyncProgress progress)? onProgress,
    SyncCancellation? cancellation,
  }) => _exclusive(
    () => _refresh(
      onProgress: onProgress,
      cancellation: cancellation ?? SyncCancellation(),
    ),
  );

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    if (_running) throw const SyncAlreadyRunning();
    _running = true;
    try {
      return await body();
    } finally {
      _running = false;
      _flushSkipFailures();
    }
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  Future<SyncSummary> _sync(
    List<String> folderPaths, {
    required void Function()? onDiscovered,
    required void Function(SyncProgress progress)? onProgress,
    required SyncCancellation cancellation,
  }) async {
    final folderRows = {for (final r in await cache.allFolderRows()) r.path: r};
    final unreadableFolders = <String>{};
    final mountByFolder = await _resolveMounts(
      folderPaths,
      folderRows,
      bindUnbound: true,
      unresolved: unreadableFolders,
    );
    final stats = await _scanFolders(mountByFolder, unreadableFolders);

    final cachedFiles = {
      for (final r in await cache.allFileRows())
        (r.folderPath, r.relativePath): r,
    };
    final cachedSeries = {
      for (final r in await cache.allSeriesRows()) r.seriesId: r,
    };
    final knownTitleToId = _knownTitles(cachedFiles.values);
    final deltas = _classifyDeltas(stats, cachedFiles, unreadableFolders);
    // A file whose bytes changed at the SAME path keeps its fix-match: the
    // override is keyed by fingerprint, so it is moved to the new one before
    // anything else runs. A `touch` used to delete the user's correction at
    // the next prune.
    final rekeys =
        <(({int size, int modifiedMs}), ({int size, int modifiedMs}))>[
          for (final key in deltas.toIdentify)
            if (cachedFiles[key] case final c?)
              if (stats[key] case final s?)
                if (c.fileSize != s.size || c.modifiedAtMs != s.modifiedMs)
                  ((size: c.fileSize, modifiedMs: c.modifiedAtMs), s),
        ];
    if (rekeys.isNotEmpty) await cache.rekeyOverrides(rekeys);

    // Parse the deltas and collect distinct titles (parse the file's basename,
    // the last segment of its relative path).
    final parsed = {
      for (final key in deltas.toIdentify) key: parser.parse(_basename(key.$2)),
    };
    final deltaTitles = <String, String>{}; // normalised -> a sample spelling
    final filesByTitle = <String, List<FileKey>>{};
    final untitled = <FileKey>[];
    for (final MapEntry(key: file, value: pf) in parsed.entries) {
      if (pf.title.isEmpty) {
        untitled.add(file);
        continue;
      }
      final norm = normalizeTitle(pf.title);
      deltaTitles.putIfAbsent(norm, () => pf.title);
      (filesByTitle[norm] ??= []).add(file);
    }

    await _writePlaceholders(deltas.toIdentify, cachedFiles, parsed, stats);
    onDiscovered?.call();

    // PHASE 2 (network): resolve each distinct delta title — reuse a cached
    // series, or search — in committed batches.
    final run = _ScanRun();
    // Resolved ONCE per run, not per title (see `SeriesMatcher.match`).
    final providers = await matcher.activeProviders();
    // The cache's ids plus what this run learns, so a freshly identified
    // show's MAL id reaches AniSkip on the same scan.
    final externalIds = Map<int, ExternalIds>.of(
      await cache.externalIdsBySeriesId(),
    );
    final answered = await _answeredSources();
    final askable = await _askableSkipSources();
    final titles = deltaTitles.entries.toList();
    try {
      for (var start = 0; start < titles.length; start += batchSize) {
        cancellation.throwIfCancelled();
        final batch = titles.sublist(
          start,
          start + batchSize > titles.length ? titles.length : start + batchSize,
        );
        final resolved = await _identify(
          batch,
          knownTitleToId,
          cachedSeries,
          providers,
          run,
          cancellation,
        );
        for (final r in resolved.values) {
          final fresh = r.freshSeries;
          final seriesId = r.seriesId;
          if (fresh != null && seriesId != null) {
            externalIds[seriesId] = fresh.externalIds.fillFrom(
              externalIds[seriesId] ?? ExternalIds.empty,
            );
          }
        }
        final seriesUpserts = await _seriesRowsFor(
          resolved.values,
          cachedSeries,
        );
        // Every file of every title in the batch — the errored ones are
        // skipped and counted inside, the resolved ones written.
        final fileUpserts = _fileRowsFor(
          [for (final e in batch) ...?filesByTitle[e.key]],
          parsed,
          stats,
          resolved,
          run,
        );
        final skipUpserts = await _fetchMissingSkipAnswers(
          _episodeKeysOf(fileUpserts),
          _pathsByEpisode(fileUpserts, mountByFolder),
          externalIds,
          answered,
          askable,
          // Every file here is new or CHANGED (that is why it is a delta), and
          // a re-encode can move or remove its chapters, so a file-reading
          // source is asked again and its row overwritten. A service keyed by
          // show and episode has nothing new to say about a changed encode.
          reaskFileSources: true,
          cancellation: cancellation,
        );
        // For every title that resolved to a real series id, carry any watch
        // progress recorded while it was a pending placeholder over to the
        // real id (rekeyed atomically in applySync). The placeholder id is the
        // same pure function the read path uses, so the keys line up; a no-op
        // for titles that never had a placeholder watched.
        final promotions = <(int, int)>[
          for (final entry in resolved.entries)
            if (entry.value.seriesId != null)
              (placeholderSeriesId(entry.key), entry.value.seriesId!),
        ];
        // No prune per batch: the three orphan sweeps run ONCE at the end of
        // the run (below). Inside every batch they were 24 full-table passes
        // per 600-title scan, each holding the write lock every UI read
        // queued behind.
        await cache.applySync(
          seriesUpserts: seriesUpserts,
          fileUpserts: fileUpserts,
          removedKeys: const [],
          skipUpserts: skipUpserts,
          promotions: promotions,
          prune: false,
        );
        run.titlesDone += batch.length;
        onProgress?.call(
          SyncProgress(
            done: run.titlesDone,
            total: titles.length,
            phase: 'identifying',
          ),
        );
      }
    } on SyncCancelled {
      run.cancelled = true;
    }

    // RESILIENCE: if every lookup we attempted failed (403 / transport /
    // timeout), then NO metadata source could answer — which is not "the
    // content is gone". The counter is per LOOKUP, not per source: each lookup
    // has already fallen through the whole ordered chain, so this being total
    // means every enabled source failed. Treat it like an unreadable folder and
    // PRESERVE the cache: skip all removals (which also makes the prune a
    // no-op, since every cached series keeps its files). A transient outage
    // must never empty a populated library; the next healthy scan reconciles
    // real moves/deletions. A CANCELLED run removes nothing either: only a run
    // that finished gets to decide what is gone.
    final apiUnreachable =
        run.attemptedLookups > 0 &&
        run.erroredTitles.length == run.attemptedLookups;
    // Only report a cause when EVERY lookup failed; a lone failure among
    // successes isn't an outage and must not accuse the user's connection.
    final reportedFailure = apiUnreachable ? run.apiFailure : null;
    final removedKeys = apiUnreachable || run.cancelled
        ? const <FileKey>[]
        : deltas.removed;

    if (!run.cancelled) {
      // Files with no parseable title are confirmed-unmatched: re-scanning
      // can't help a name the parser can't read, so they go to fix-match.
      final untitledRows = _fileRowsFor(untitled, parsed, stats, const {}, run);
      if (untitledRows.isNotEmpty || removedKeys.isNotEmpty) {
        await cache.applySync(
          seriesUpserts: const [],
          fileUpserts: untitledRows,
          removedKeys: removedKeys,
          prune: false,
        );
      }
      // The one prune of the run: series no file or override references any
      // more (re-identified away, or removed above), their skip answers, and
      // fix-match overrides whose file is gone from every folder.
      await cache.pruneOrphans();
      if (!apiUnreachable) {
        // The prune dropped series nobody references; their covers go
        // too. Only a run that saw every source answer gets to delete art —
        // an outage must never look like a library shrinking.
        final live = {for (final r in await cache.allSeriesRows()) r.seriesId};
        await art.deleteExcept(live);
      }
    }

    return SyncSummary(
      filesScanned: stats.length,
      unchanged: deltas.unchanged,
      processed: run.matched + run.unmatched,
      removed: removedKeys.length,
      matched: run.matched,
      unmatched: run.unmatched,
      errored: run.errored,
      lookupsBySource: run.lookupsBySource,
      unreadableFolders: unreadableFolders.toList(),
      apiFailure: reportedFailure,
      cancelled: run.cancelled,
      skipLookupsFailed: _skipFailureCount,
      sourcesDown: [...run.health.down, ..._skipHealth.down],
    );
  }

  /// Stable folder identity -> where it is mounted RIGHT NOW.
  ///
  /// Kept because a local skip source reads the episode's file, and building
  /// that path from the stable identity handed it a dangling path whenever a
  /// volume had remounted under another name. A folder whose volume isn't
  /// mounted is reported in [unresolved] (its cached files are PRESERVED, never
  /// dropped) and gets no entry. With [bindUnbound], a folder that has a row
  /// but no volume binding yet is bound now — migrated folders and freshly
  /// added ones; the resolver returns null for internal-disk paths, so only
  /// removable/network volumes get bound, they being the ones whose mount name
  /// can change. Best-effort.
  Future<Map<String, String>> _resolveMounts(
    Iterable<String> folderPaths,
    Map<String, LibraryFolderRow> folderRows, {
    required bool bindUnbound,
    Set<String>? unresolved,
  }) async {
    final mountByFolder = <String, String>{};
    for (final folderPath in folderPaths) {
      final row = folderRows[folderPath];
      final current = await resolveFolderPath(
        storedPath: folderPath,
        volumeId: row?.volumeId,
        volumeSubpath: row?.volumeSubpath,
        resolver: resolver,
      );
      if (current == null) {
        unresolved?.add(folderPath);
        continue;
      }
      mountByFolder[folderPath] = current;
      if (bindUnbound && row != null && row.volumeId == null) {
        final info = await resolver.infoForPath(current);
        if (info == null) {
          AppLog.warn('Volume binding skipped: no volume info for $current');
          continue;
        }
        final subpath = volumeSubpathOf(current, info.mountPoint);
        if (subpath == null) {
          AppLog.warn(
            'Volume binding skipped: $current is not under ${info.mountPoint}',
          );
          continue;
        }
        await cache.bindFolderVolume(folderPath, info.volumeId, subpath);
      }
    }
    return mountByFolder;
  }

  /// Every video file under each mounted folder, keyed by identity, with its
  /// fingerprint. The walk and the stats run off the UI isolate (see
  /// [FolderScanner.statVideoFiles]). A folder that fails to list is added to
  /// [unreadable] and its cached files are preserved (access lapsed, not
  /// deleted).
  Future<Map<FileKey, FileSig>> _scanFolders(
    Map<String, String> mountByFolder,
    Set<String> unreadable,
  ) async {
    final stats = <FileKey, FileSig>{};
    // Every mount, so a file under a NESTED folder rebases against the most
    // specific one and is written once, not once per enclosing folder.
    final mounts = mountByFolder.values.toList();
    for (final MapEntry(key: folderPath, value: current)
        in mountByFolder.entries) {
      try {
        final found = await scanner.statVideoFiles(current);
        // A drive pulled DURING the walk leaves a partial listing behind. A
        // partial listing would classify every unlisted file as removed and
        // delete it at the end of the run; a root that is gone now says the
        // folder was unreadable, which preserves its files.
        if (!await Directory(current).exists()) {
          AppLog.warn('Scan: $folderPath vanished during the walk');
          unreadable.add(folderPath);
          continue;
        }
        for (final MapEntry(key: abs, value: sig) in found.entries) {
          final key = rebaseToFolderRelative(abs, mounts);
          if (key.folderPath != current) continue; // a nested folder's file
          stats[(folderPath, key.relativePath)] = sig;
        }
      } on FileSystemException catch (e) {
        AppLog.warn('Scan: could not read $folderPath', error: e);
        unreadable.add(folderPath);
      }
    }
    return stats;
  }

  /// A known title -> its cached series, so a delta of an already-known series
  /// never hits the network.
  Map<String, int> _knownTitles(Iterable<CachedFileRow> cached) {
    final known = <String, int>{};
    for (final r in cached) {
      if (r.seriesId != null && r.parsedTitle.isNotEmpty) {
        known.putIfAbsent(normalizeTitle(r.parsedTitle), () => r.seriesId!);
      }
    }
    return known;
  }

  /// Classify scanned files against the cache (by identity).
  ///
  /// A file is only "unchanged" (skipped) when its bytes match AND it isn't a
  /// PENDING placeholder — a pending row is unidentified, so it's re-attempted
  /// every scan (this is how it auto-resolves once back online) even though the
  /// file on disk hasn't changed. A confirmed-unmatched row (seriesId null,
  /// pending false) is NOT retried — it stays put until fix-match. Removed =
  /// cached files not found this scan, EXCEPT those under a folder we couldn't
  /// read/resolve (preserve those — access lapsed or volume unplugged).
  _Deltas _classifyDeltas(
    Map<FileKey, FileSig> stats,
    Map<FileKey, CachedFileRow> cachedFiles,
    Set<String> unreadableFolders,
  ) {
    final toIdentify = <FileKey>[];
    var unchanged = 0;
    for (final MapEntry(key: key, value: s) in stats.entries) {
      final c = cachedFiles[key];
      final bytesUnchanged =
          c != null && c.fileSize == s.size && c.modifiedAtMs == s.modifiedMs;
      final isPending =
          c != null && c.seriesId == null && c.pendingIdentification;
      if (bytesUnchanged && !isPending) {
        unchanged++;
      } else {
        toIdentify.add(key);
      }
    }
    final removed = [
      for (final key in cachedFiles.keys)
        if (!stats.containsKey(key) && !unreadableFolders.contains(key.$1)) key,
    ];
    return _Deltas(
      toIdentify: toIdentify,
      unchanged: unchanged,
      removed: removed,
    );
  }

  /// PHASE 1 (no network): write every NEWLY-SEEN, titled file as a pending
  /// placeholder. "New" = not already in the cache, so an already-matched file
  /// whose bytes changed is NOT briefly demoted to a placeholder — it keeps its
  /// match until phase 2 re-resolves it. Files with no parseable title are left
  /// for the final commit (they become confirmed-unmatched; re-scanning can't
  /// help a name the parser can't read). Phase 2's upserts overwrite these rows
  /// in place; rows whose lookup errors simply remain as written here.
  Future<void> _writePlaceholders(
    List<FileKey> toIdentify,
    Map<FileKey, CachedFileRow> cachedFiles,
    Map<FileKey, ParsedFilename> parsed,
    Map<FileKey, FileSig> stats,
  ) async {
    final rows = <CachedFileRow>[];
    for (final key in toIdentify) {
      final pf = parsed[key]!;
      if (cachedFiles[key] != null || pf.title.isEmpty) continue;
      final s = stats[key]!;
      rows.add(
        CachedFileRow(
          folderPath: key.$1,
          relativePath: key.$2,
          fileSize: s.size,
          modifiedAtMs: s.modifiedMs,
          seriesId: null,
          episodeNumber: pf.episodeNumber,
          parsedTitle: pf.title,
          matchScore: 0,
          releaseGroup: pf.releaseGroup,
          pendingIdentification: true,
        ),
      );
    }
    if (rows.isNotEmpty) await cache.upsertFiles(rows);
  }

  /// Resolve a batch of distinct titles: a cached series where the title is
  /// already known, otherwise a search through [providers].
  ///
  /// Identity is OURS, not the provider's. `ensureSeriesId` recognises a show
  /// another provider already identified (matching on ANY id the answer
  /// carries) and mints only when nothing matches — without this the same show
  /// would fork under two ids and strand watch progress. A candidate carrying
  /// no ids at all cannot be given an identity (`ensureSeriesId` would throw);
  /// it is a no-match, exactly as fix-match refuses it. No shipped mapper
  /// produces one, so this is the guard, not a path. A transient failure
  /// records the title in [run] and writes nothing for it, so its files keep
  /// what they were and it is retried next scan.
  Future<Map<String, _Resolved>> _identify(
    List<MapEntry<String, String>> titles,
    Map<String, int> knownTitleToId,
    Map<int, CachedSeriesRow> cachedSeries,
    List<MetadataProvider> providers,
    _ScanRun run,
    SyncCancellation cancellation,
  ) async {
    final resolved = <String, _Resolved>{};
    for (final MapEntry(key: norm, value: sample) in titles) {
      cancellation.throwIfCancelled();
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
        run.attemptedLookups++;
        final result = await matcher.match(
          sample,
          providers: providers,
          health: run.health,
        );
        final found = result.series;
        final seriesId = found == null || found.externalIds.isEmpty
            ? null
            : await cache.ensureSeriesId(found.externalIds);
        final source = result.source;
        if (source != null) {
          run.lookupsBySource[source] = (run.lookupsBySource[source] ?? 0) + 1;
        }
        resolved[norm] = _Resolved(
          seriesId: seriesId,
          score: result.score,
          freshSeries: found,
        );
      } on MetadataException catch (e) {
        run.erroredTitles.add(norm); // transient — skip, retry next scan
        // First cause wins: an outage fails every lookup the same way, and the
        // first is the one that isn't a knock-on effect of a degrading API.
        run.apiFailure ??= e.failure;
      }
    }
    return resolved;
  }

  /// Cache rows (with downloaded art) for the freshly fetched series only —
  /// incremental. Art is filed under OUR id, not the provider's: they diverge
  /// as soon as a show is identified by a source other than AniList.
  Future<List<CachedSeriesRow>> _seriesRowsFor(
    Iterable<_Resolved> resolved,
    Map<int, CachedSeriesRow> cachedSeries,
  ) async {
    final wanted = [
      for (final r in resolved)
        if (r.freshSeries != null && r.seriesId != null) r,
    ];
    // Covers download [kArtConcurrency] at a time. One at a time, 600 new
    // shows were two minutes of serial round trips holding up the batch
    // commit; unbounded would hammer one CDN from one address.
    final artPaths = await mapLimited(wanted, kArtConcurrency, (r) {
      // The previous cover travels along on EVERY path (this one used not to),
      // so a show re-identified by a different source replaces its picture.
      final prior = cachedSeries[r.seriesId!];
      return art.ensureCover(
        r.seriesId!,
        r.freshSeries!.coverImageRef,
        cachedUrl: prior?.coverImageUrl,
        cachedPath: prior?.coverImagePath,
      );
    });
    return [
      for (var i = 0; i < wanted.length; i++)
        _seriesRow(wanted[i].freshSeries!, artPaths[i], wanted[i].seriesId!),
    ];
  }

  /// Final (identified) file rows for [files]. A file whose title errored this
  /// run is NOT written, so it KEEPS whatever it already is — a new file stays
  /// the pending placeholder from phase 1 (retried next scan), an
  /// already-matched changed file keeps its match. Everything else is written
  /// with pendingIdentification=false: a match (seriesId set) or a genuine
  /// no-match (seriesId null = confirmed-unmatched, the fix-match screen).
  List<CachedFileRow> _fileRowsFor(
    List<FileKey> files,
    Map<FileKey, ParsedFilename> parsed,
    Map<FileKey, FileSig> stats,
    Map<String, _Resolved> resolved,
    _ScanRun run,
  ) {
    final rows = <CachedFileRow>[];
    for (final key in files) {
      final pf = parsed[key]!;
      final norm = pf.title.isEmpty ? null : normalizeTitle(pf.title);
      if (norm != null && run.erroredTitles.contains(norm)) {
        run.errored++;
        continue;
      }
      final res = norm == null ? null : resolved[norm];
      final seriesId = res?.seriesId;
      final s = stats[key]!;
      rows.add(
        CachedFileRow(
          folderPath: key.$1,
          relativePath: key.$2,
          fileSize: s.size,
          modifiedAtMs: s.modifiedMs,
          seriesId: seriesId,
          episodeNumber: pf.episodeNumber,
          parsedTitle: pf.title,
          matchScore: res?.score ?? 0,
          releaseGroup: pf.releaseGroup,
          pendingIdentification: false,
        ),
      );
      if (seriesId != null) {
        run.matched++;
      } else {
        run.unmatched++;
      }
    }
    return rows;
  }

  /// One episode identity per distinct (series, episode) — deduped across
  /// multi-source files.
  Set<EpisodeKey> _episodeKeysOf(Iterable<CachedFileRow> files) => {
    for (final f in files)
      if (f.seriesId != null && f.episodeNumber != null)
        (f.seriesId!, f.episodeNumber!),
  };

  /// A LOCAL skip source reads the episode's own file, so the lookup has to
  /// carry its absolute path — from the folder's CURRENT mount plus the
  /// relative path the cache is keyed by. An unmounted folder yields no path,
  /// so a local source records nothing for its episodes rather than "asked,
  /// had nothing".
  Map<EpisodeKey, String> _pathsByEpisode(
    Iterable<CachedFileRow> files,
    Map<String, String> mountByFolder,
  ) {
    final paths = <EpisodeKey, String>{};
    for (final f in files) {
      final mount = mountByFolder[f.folderPath];
      if (f.seriesId == null || f.episodeNumber == null || mount == null) {
        continue;
      }
      paths.putIfAbsent((
        f.seriesId!,
        f.episodeNumber!,
      ), () => '$mount/${f.relativePath}');
    }
    return paths;
  }

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------

  Future<RefreshSummary> _refresh({
    required void Function(SyncProgress progress)? onProgress,
    required SyncCancellation cancellation,
  }) async {
    final files = await cache.allFileRows();
    final overrides = {
      for (final o in await cache.allOverrideRows())
        (o.fileSize, o.modifiedAtMs): o,
    };
    // Every series the library references (auto-matched files + overrides).
    final ids = <int>{
      for (final f in files)
        if (f.seriesId != null) f.seriesId!,
      for (final o in overrides.values) o.seriesId,
    };
    // Read ONCE: every provider is re-asked BY ITS OWN ids (which is why the
    // side table exists — our series_id means nothing to Kitsu or MAL), and
    // the same map seeds the skip lookups' MAL ids below. Seeded from the
    // CACHE, so a refresh whose fetch fails still knows the MAL ids it already
    // stored and skips can still be backfilled offline.
    final externalIds = Map<int, ExternalIds>.of(
      await cache.externalIdsBySeriesId(),
    );
    final cachedSeriesRows = {
      for (final r in await cache.allSeriesRows()) r.seriesId: r,
    };

    var seriesRefreshed = 0;
    MetadataFailure? failure;
    var cancelled = false;
    try {
      for (final provider in await matcher.activeProviders()) {
        cancellation.throwIfCancelled();
        if (!await provider.isConfigured()) continue;
        final refreshed = await _refreshWith(
          provider,
          ids,
          externalIds,
          cachedSeriesRows,
        );
        if (refreshed == null) {
          // Transient — keep existing metadata and try the next source.
          // Reported rather than swallowed: a silent catch here made an
          // outage look like a successful "Refreshed 0 series".
          failure = _lastRefreshFailure;
          continue;
        }
        if (refreshed == 0) continue; // held no ids for this source
        seriesRefreshed = refreshed;
        failure = null;
        break; // the preferred source answered; lower ones are the fallback
      }
      onProgress?.call(
        SyncProgress(done: ids.length, total: ids.length, phase: 'metadata'),
      );

      // Effective (seriesId, anchored) per matched file — overrides win, so
      // fix-matched episodes get skips keyed to their corrected identity. The
      // FILE is carried alongside because a LOCAL skip source reads it. This
      // path matters more than it looks: a scan only fetches skips for files
      // it is already reprocessing (new or changed), so for a library that is
      // already scanned, refresh is the ONLY way a newly-added skip source
      // ever reaches the existing episodes. Every folder a cached file lives
      // in is resolved — not only the ones with a library_folders row, since a
      // folder scanned by path alone still has files here.
      final folderRows = {
        for (final r in await cache.allFolderRows()) r.path: r,
      };
      final mountByFolder = await _resolveMounts(
        {for (final f in files) f.folderPath},
        folderRows,
        bindUnbound: false,
      );
      final effective = <CachedFileRow>[
        for (final f in files)
          ?_effectiveRow(f, overrides[(f.fileSize, f.modifiedAtMs)]),
      ];
      final rows = await _fetchMissingSkipAnswers(
        _episodeKeysOf(effective),
        _pathsByEpisode(effective, mountByFolder),
        externalIds,
        await _answeredSources(),
        await _askableSkipSources(),
        reaskFileSources: false,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      await cache.upsertSkipAnswers(rows);
      // Count episodes that gained a usable window, which is what the user is
      // told; an answer of "nothing here" is progress but not a skip.
      final skipsFetched = {
        for (final r in rows)
          if (r.introStartMs != null || r.outroStartMs != null)
            (r.seriesId, r.episode),
      }.length;
      return RefreshSummary(
        seriesRefreshed: seriesRefreshed,
        skipsFetched: skipsFetched,
        failure: failure,
        skipLookupsFailed: _skipFailureCount,
      );
    } on SyncCancelled {
      cancelled = true;
    }
    return RefreshSummary(
      seriesRefreshed: seriesRefreshed,
      skipsFetched: 0,
      failure: failure,
      skipLookupsFailed: _skipFailureCount,
      cancelled: cancelled,
    );
  }

  MetadataFailure? _lastRefreshFailure;

  /// Re-fetch every series [provider] has an id for and write the answers in
  /// ONE transaction. Returns how many were refreshed, 0 when we hold no ids
  /// this source can use, or null when the source failed (the cause is left
  /// in [_lastRefreshFailure]).
  Future<int?> _refreshWith(
    MetadataProvider provider,
    Set<int> ids,
    Map<int, ExternalIds> externalIds,
    Map<int, CachedSeriesRow> cachedSeriesRows,
  ) async {
    // series_id <-> this provider's id, for the ids we actually hold. By
    // idNamespace, not token: Jikan's ids are MyAnimeList's and live under
    // `mal`. Looked up by token, this map was empty for Jikan and MAL and
    // neither source could ever refresh anything.
    final providerIdBySeries = <int, int>{
      for (final seriesId in ids)
        seriesId: ?externalIds[seriesId]?.forProvider(provider.idNamespace),
    };
    if (providerIdBySeries.isEmpty) return 0;
    final seriesByProviderId = {
      for (final e in providerIdBySeries.entries) e.value: e.key,
    };

    final List<Series> fetched;
    try {
      fetched = await provider.fetchByProviderIds(
        providerIdBySeries.values.toList(),
      );
    } on MetadataException catch (e) {
      _lastRefreshFailure = e.failure;
      return null;
    }

    // Network first (art), then one transaction for every row: a failure or
    // a quit mid-way leaves the cache as it was rather than half-refreshed.
    final writes = <(int seriesId, Series fresh, String? artPath)>[];
    for (final fresh in fetched) {
      // Map the provider's answer back onto OUR identity — never adopt the
      // provider's id as the key. Answered about something we didn't ask for
      // -> skipped.
      final providerId = fresh.externalIds.forProvider(provider.idNamespace);
      final seriesId = seriesByProviderId[providerId];
      if (seriesId == null) continue;
      final prior = cachedSeriesRows[seriesId];
      // Previous cover carried along, so a source switch actually replaces the
      // art instead of keeping the first source's picture forever.
      final artPath = await art.ensureCover(
        seriesId,
        fresh.coverImageRef,
        cachedUrl: prior?.coverImageUrl,
        cachedPath: prior?.coverImagePath,
      );
      writes.add((seriesId, fresh, artPath));
    }
    await cache.transaction(() async {
      for (final (seriesId, fresh, artPath) in writes) {
        // A null field here CANNOT blank a cached value: upsertSeries goes
        // through drift's insertOnConflictUpdate, whose DO UPDATE SET omits
        // null columns. So a degraded payload, or a cover download that
        // failed, leaves the existing row's fields intact — the no-wipe
        // guarantee this method promises. Pinned by
        // test/metadata_refresh_failure_test.dart.
        await cache.upsertSeries(_seriesRow(fresh, artPath, seriesId));
        // Learn any ids this answer carried that we didn't have.
        final merged = fresh.externalIds.fillFrom(
          externalIds[seriesId] ?? ExternalIds.empty,
        );
        await cache.ensureSeriesId(merged);
        externalIds[seriesId] = merged;
      }
    });
    return writes.length;
  }

  /// A file's effective identity row: the override's series and anchored
  /// episode when one exists, else its own match, else null (unmatched).
  CachedFileRow? _effectiveRow(CachedFileRow f, MatchOverrideRow? o) {
    if (o != null) {
      return f.copyWith(
        seriesId: Value(o.seriesId),
        episodeNumber: Value(o.anchoredEpisode ?? 0),
      );
    }
    if (f.seriesId == null) return null;
    return f.episodeNumber == null
        ? f.copyWith(episodeNumber: const Value(0))
        : f;
  }

  // ---------------------------------------------------------------------------
  // Skip sources (shared by both entry points)
  // ---------------------------------------------------------------------------

  /// Which sources have already answered for each episode.
  Future<Map<EpisodeKey, Set<String>>> _answeredSources() async {
    final answered = <EpisodeKey, Set<String>>{};
    for (final a in await cache.allSkipAnswers()) {
      (answered[(a.seriesId, a.episode)] ??= <String>{}).add(a.source);
    }
    return answered;
  }

  /// Ask every source that has not yet answered for each of [episodes], and
  /// return the rows to store. Rows for the episodes asked here are added to
  /// [answered] so a later batch in the same run does not ask again.
  ///
  /// A source that already answered for an episode — even to say it had
  /// nothing — is not asked again; that is what keeps refresh incremental now
  /// that there is no resolution key. [reaskFileSources] is the scan path's
  /// exception for sources whose answer is derived from a file that changed.
  Future<List<SkipSourceAnswerRow>> _fetchMissingSkipAnswers(
    Set<EpisodeKey> episodes,
    Map<EpisodeKey, String> pathByEpisode,
    Map<int, ExternalIds> externalIds,
    Map<EpisodeKey, Set<String>> answered,
    List<SkipProvider> askable, {
    required bool reaskFileSources,
    required SyncCancellation cancellation,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    if (askable.isEmpty || episodes.isEmpty) return const [];
    final malIds = await _resolveMalIds(externalIds, episodes.map((k) => k.$1));
    final rows = <SkipSourceAnswerRow>[];
    var done = 0;
    for (final key in episodes) {
      cancellation.throwIfCancelled();
      final (seriesId, episode) = key;
      final already = answered[key] ?? const <String>{};
      final missing = [
        for (final p in askable)
          if ((reaskFileSources && p.readsFile) || !already.contains(p.token))
            p,
      ];
      if (missing.isNotEmpty) {
        final answers = await _askSkipSources(
          SkipLookup(
            seriesId: seriesId,
            episode: episode,
            malId: malIds[seriesId],
            filePath: pathByEpisode[key],
          ),
          missing,
        );
        rows.addAll(answers);
        (answered[key] ??= <String>{}).addAll(answers.map((r) => r.source));
      }
      done++;
      if (onProgress != null && (done % 25 == 0 || done == episodes.length)) {
        onProgress(
          SyncProgress(done: done, total: episodes.length, phase: 'skips'),
        );
      }
    }
    return rows;
  }

  /// The skip sources worth asking: enabled, in the user's order, and
  /// actually configured.
  ///
  /// ONE place decides this so the scan and the refresh cannot disagree about
  /// which sources are in play. Read fresh, so enabling a source takes effect
  /// on the next scan or refresh without a restart. An unconfigured source
  /// (awaiting a client ID) cannot answer, and asking it would only record a
  /// false "it had nothing" that stops it ever being asked again.
  Future<List<SkipProvider>> _askableSkipSources() async {
    final askable = <SkipProvider>[];
    for (final provider in await _activeSkipProviders()) {
      if (await provider.isConfigured()) askable.add(provider);
    }
    return askable;
  }

  /// The enabled skip sources, in the user's order.
  Future<List<SkipProvider>> _activeSkipProviders() async {
    final load = loadSkipOrder;
    return applySourceOrder(
      skipProviders,
      (p) => p.token,
      load == null ? const [] : await load(),
    );
  }

  /// Skip-source failures seen during the current run, by source and cause;
  /// written to the log as one line each by `_flushSkipFailures`.
  final _skipFailures = <(String, MetadataFailure), int>{};

  /// Per-run circuit breaker for skip sources — see [SourceHealth].
  var _skipHealth = SourceHealth();

  int get _skipFailureCount =>
      _skipFailures.values.fold(0, (sum, n) => sum + n);

  void _flushSkipFailures() {
    for (final MapEntry(key: (source, failure), value: count)
        in _skipFailures.entries) {
      AppLog.warn(
        'Skip source $source failed for $count episode(s): ${failure.name} — '
        'no rows written, retried next run',
      );
    }
    _skipFailures.clear();
    _skipHealth = SourceHealth();
  }

  /// Ask each source and record WHAT IT SAID — no reconciliation here.
  ///
  /// Which window wins and how far to trust it are read-path decisions now
  /// (`resolveEpisodeSkips`), so this writes raw answers and nothing derived.
  /// That is what removed the need to invalidate anything when those rules
  /// change.
  ///
  /// Three outcomes, and the differences between them are the whole contract:
  /// a source with WINDOWS stores them; a source with NOTHING stores a row of
  /// nulls, so it is never asked again; a source that FAILED stores no row at
  /// all, so a later scan or refresh retries it. Partial coverage is the norm
  /// here, which is why "had nothing" must be recordable rather than looking
  /// like a failure forever.
  Future<List<SkipSourceAnswerRow>> _askSkipSources(
    SkipLookup lookup,
    List<SkipProvider> providers,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <SkipSourceAnswerRow>[];
    for (final provider in providers) {
      // "Could not try" writes nothing, so it is retried once the lookup
      // carries what this source needs — an AniSkip id the cross-map supplies
      // later, say. Only a real answer, including "I have nothing", is stored.
      if (!await provider.canAnswer(lookup)) continue;
      // The run's breaker: a source that could not be reached twice in a row
      // is not asked again this run (each ask is a full timeout).
      if (_skipHealth.isDown(provider.token)) continue;
      final EpisodeSkips? found;
      try {
        found = await provider.fetchSkips(lookup);
        _skipHealth.succeeded(provider.token);
      } on SkipException catch (e) {
        _skipHealth.failed(provider.token, e.failure);
        // Transient — no row, so it is retried. Tallied, not logged here: a
        // source failing for 400 episodes in a row used to look identical to
        // one that had nothing, and then, once logged per episode, it evicted
        // everything else from the diagnostics ring. One line per run instead.
        final key = (provider.token, e.failure);
        _skipFailures[key] = (_skipFailures[key] ?? 0) + 1;
        continue;
      }
      rows.add(
        SkipSourceAnswerRow(
          seriesId: lookup.seriesId,
          episode: lookup.episode,
          source: provider.token,
          introStartMs: found?.intro?.start.inMilliseconds,
          introEndMs: found?.intro?.end.inMilliseconds,
          outroStartMs: found?.outro?.start.inMilliseconds,
          outroEndMs: found?.outro?.end.inMilliseconds,
          askedAtMs: now,
        ),
      );
    }
    return rows;
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
    Map<int, ExternalIds> ids,
    Iterable<int> seriesIds,
  ) async {
    final known = <int, int?>{for (final id in seriesIds) id: ids[id]?.mal};
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
      // The map is keyed by ANILIST id. That equals our series_id only in the
      // provider-seeded band; a minted show that later learned its AniList id
      // keeps its minted key, so the lookup must go through the side table.
      final anilistId = ids[id]?.anilist;
      if (anilistId == null) continue;
      final mal = map.malFor(anilistId);
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

  String _basename(String path) => basenameOf(path);
}

/// Scanned files split against the cache: what to (re)identify, what was
/// unchanged, what is gone.
class _Deltas {
  const _Deltas({
    required this.toIdentify,
    required this.unchanged,
    required this.removed,
  });

  final List<FileKey> toIdentify;
  final int unchanged;
  final List<FileKey> removed;
}

/// Counters and outcomes accumulated across a scan's batches.
class _ScanRun {
  /// The run's circuit breaker for metadata sources — see [SourceHealth].
  final health = SourceHealth();
  final erroredTitles = <String>{};
  final lookupsBySource = <String, int>{};
  int attemptedLookups = 0;
  MetadataFailure? apiFailure;
  int matched = 0;
  int unmatched = 0;
  int errored = 0;
  int titlesDone = 0;
  bool cancelled = false;
}

/// Per-title resolution result during a sync.
class _Resolved {
  _Resolved({required this.seriesId, required this.score, this.freshSeries});

  final int? seriesId;
  final double score;

  /// Non-null only when freshly fetched from a source (needs caching + art).
  final Series? freshSeries;
}

/// How many cover downloads run at once during a scan.
const int kArtConcurrency = 4;

/// [items] mapped through [f] with at most [limit] in flight, results in
/// input order. A small bounded pool, not `Future.wait` over everything.
Future<List<T>> mapLimited<S, T>(
  List<S> items,
  int limit,
  Future<T> Function(S item) f,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await f(items[i]);
    }
  }

  await Future.wait([
    for (var w = 0; w < limit && w < items.length; w++) worker(),
  ]);
  return [for (final r in results) r as T];
}
