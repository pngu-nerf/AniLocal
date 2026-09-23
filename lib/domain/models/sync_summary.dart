import 'package:equatable/equatable.dart';

import 'metadata_failure.dart';

/// Outcome of a library refresh (fill path), surfaced to the UI. A domain model
/// so the UI can render it without importing sync/cache types (seam #1).
class SyncSummary extends Equatable {
  const SyncSummary({
    required this.filesScanned,
    required this.unchanged,
    required this.processed,
    required this.removed,
    required this.matched,
    required this.unmatched,
    required this.errored,
    this.lookupsBySource = const {},
    this.unreadableFolders = const [],
    this.apiFailure,
    this.cancelled = false,
    this.skipLookupsFailed = 0,
    this.sourcesDown = const [],
    this.airingChecked = 0,
  });

  /// Total video files found on disk.
  final int filesScanned;

  /// Files skipped because path + size + mtime were unchanged.
  final int unchanged;

  /// New/changed files (re)identified this run.
  final int processed;

  /// Cached files whose backing file is gone, removed from the cache.
  final int removed;

  /// Of [processed], how many matched a series vs. recorded as unmatched.
  final int matched;
  final int unmatched;

  /// Delta files whose lookup hit a transient source error this scan. They are
  /// NOT dropped — a new file stays the pending placeholder written in phase 1
  /// (shown named in the library) and is retried next scan; an already-matched
  /// changed file keeps its existing match.
  final int errored;

  /// Title searches actually performed, BY SOURCE TOKEN — empty when every
  /// delta reused an already-cached series (proves "never refetch unchanged").
  ///
  /// Per source rather than one total because there are several now: a scan
  /// that fell through to Kitsu because AniList was down looks identical to one
  /// AniList served, and the user has no other way to tell.
  final Map<String, int> lookupsBySource;

  /// Total across every source.
  int get totalLookups =>
      lookupsBySource.values.fold(0, (sum, count) => sum + count);

  /// Watched folders that could not be read this scan (e.g. access lapsed or
  /// folder moved). Surfaced loudly; their cached files are preserved, never
  /// silently dropped.
  final List<String> unreadableFolders;

  /// Set when every metadata lookup this scan failed — the sources are unreachable,
  /// not "the content is gone". Like an unreadable folder, the cache is
  /// PRESERVED (no removals/prune) so a transient outage can't empty a
  /// populated library. Carries WHOSE end the fault is on so the UI can tell
  /// the user whether to check their connection or just wait. Null = no
  /// failure.
  final MetadataFailure? apiFailure;

  /// Whether every metadata lookup failed this scan. Derived from
  /// [apiFailure] so the flag and the reason can never disagree.
  bool get apiUnreachable => apiFailure != null;

  /// The user stopped the scan. Everything counted here was COMMITTED before
  /// the stop; no removals were applied, and the titles not yet identified
  /// remain pending placeholders that the next scan picks up.
  final bool cancelled;

  /// Skip lookups that FAILED this run (a network error, not "no data") and
  /// were not stored, so they are retried next scan. A scan used to say
  /// nothing about them.
  final int skipLookupsFailed;

  /// Sources marked unreachable during this run and skipped for the rest of
  /// it — see `SourceHealth`. Named so the user knows why lookups were fast
  /// and empty.
  final List<String> sourcesDown;

  /// Shows whose broadcast state was re-asked this run (phase 4).
  final int airingChecked;

  @override
  List<Object?> get props => [
    filesScanned,
    unchanged,
    processed,
    removed,
    matched,
    unmatched,
    errored,
    lookupsBySource,
    unreadableFolders,
    apiFailure,
    cancelled,
    airingChecked,
  ];
}
