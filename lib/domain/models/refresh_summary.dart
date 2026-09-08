import 'package:equatable/equatable.dart';

import 'metadata_failure.dart';

/// Outcome of a "Refresh metadata" backfill, surfaced to the UI.
///
/// A named domain model rather than an inline record so the shape lives in ONE
/// place (it is threaded through four UI signatures), and so the refresh has
/// somewhere to report [failure] — without it a metadata refresh during an
/// AniList outage reported a cheerful "Refreshed 0 series" success.
class RefreshSummary extends Equatable {
  const RefreshSummary({
    required this.seriesRefreshed,
    required this.skipsFetched,
    this.failure,
  });

  /// Series whose metadata was re-fetched and upserted.
  final int seriesRefreshed;

  /// Episode identities that gained a cached AniSkip row this run.
  final int skipsFetched;

  /// Why the AniList half of the refresh failed, or null when it succeeded.
  /// The cache is left untouched either way — a refresh never wipes.
  final MetadataFailure? failure;

  /// True when AniList could not be reached at all this run. Derived from
  /// [failure] so the two can never disagree.
  bool get apiUnreachable => failure != null;

  @override
  List<Object?> get props => [seriesRefreshed, skipsFetched, failure];
}
