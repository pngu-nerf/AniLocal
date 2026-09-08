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
    required this.anilistLookups,
    this.unreadableFolders = const [],
    this.apiFailure,
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

  /// Set when every AniList lookup this scan failed — the API is unreachable,
  /// not "the content is gone". Like an unreadable folder, the cache is
  /// PRESERVED (no removals/prune) so a transient outage can't empty a
  /// populated library. Carries WHOSE end the fault is on so the UI can tell
  /// the user whether to check their connection or just wait. Null = no
  /// failure.
  final MetadataFailure? apiFailure;

  /// Whether AniList was unreachable this scan. Derived from [apiFailure] so
  /// the flag and the reason can never disagree.
  bool get apiUnreachable => apiFailure != null;

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
    apiFailure,
  ];
}
