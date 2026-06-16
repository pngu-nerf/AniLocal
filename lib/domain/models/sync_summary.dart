import 'package:equatable/equatable.dart';

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
    required this.anilistLookups,
    this.unreadableFolders = const [],
    this.apiUnreachable = false,
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

  /// Delta files whose lookup hit a transient AniList error this scan. They are
  /// NOT dropped — a new file stays the pending placeholder written in phase 1
  /// (shown named in the library) and is retried next scan; an already-matched
  /// changed file keeps its existing match.
  final int errored;

  /// AniList title searches actually performed — 0 when every delta reused an
  /// already-cached series (proves "never refetch unchanged").
  final int anilistLookups;

  /// Watched folders that could not be read this scan (e.g. access lapsed or
  /// folder moved). Surfaced loudly; their cached files are preserved, never
  /// silently dropped.
  final List<String> unreadableFolders;

  /// Every AniList lookup this scan failed (403 / transport / timeout) — the
  /// API is unreachable, not "the content is gone". Like an unreadable folder,
  /// the cache is PRESERVED (no removals/prune) so a transient outage can't
  /// empty a populated library. Surfaced so the user knows to retry.
  final bool apiUnreachable;

  @override
  List<Object?> get props => [
    filesScanned,
    unchanged,
    processed,
    removed,
    matched,
    unmatched,
    errored,
    anilistLookups,
    unreadableFolders,
    apiUnreachable,
  ];
}
