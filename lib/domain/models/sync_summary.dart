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

  /// Files skipped due to a transient AniList error (not cached; retried next).
  final int errored;

  /// AniList title searches actually performed — 0 when every delta reused an
  /// already-cached series (proves "never refetch unchanged").
  final int anilistLookups;

  /// Watched folders that could not be read this scan (e.g. access lapsed or
  /// folder moved). Surfaced loudly; their cached files are preserved, never
  /// silently dropped.
  final List<String> unreadableFolders;

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
  ];
}
