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
    this.skipLookupsFailed = 0,
    this.cancelled = false,
  });

  /// Series whose metadata was re-fetched and upserted.
  final int seriesRefreshed;

  /// Episode identities that gained a usable skip window this run.
  final int skipsFetched;

  /// Why the metadata half of the refresh failed, or null when it succeeded.
  /// The cache is left untouched either way — a refresh never wipes.
  final MetadataFailure? failure;

  /// True when no metadata source could be reached this run. Derived from
  /// [failure] so the two can never disagree.
  bool get apiUnreachable => failure != null;

  /// Skip-source lookups that FAILED (as opposed to answering "nothing") and
  /// wrote no row. Reported because a refresh where AniSkip rate-limited every
  /// episode used to read "0 skip sets fetched" — indistinguishable from a
  /// library that already had them all.
  final int skipLookupsFailed;

  /// The user stopped the refresh; what is counted was committed first.
  final bool cancelled;

  @override
  List<Object?> get props => [
    seriesRefreshed,
    skipsFetched,
    failure,
    skipLookupsFailed,
    cancelled,
  ];
}
