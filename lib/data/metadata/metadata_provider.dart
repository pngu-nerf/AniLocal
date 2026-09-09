import '../../domain/models/metadata_failure.dart';
import '../../domain/models/series.dart';

/// Thrown when a provider cannot answer. Carries [failure] so the UI can say
/// WHOSE end the fault is on (see `metadata_failure_message.dart`), and so the
/// fallback chain can tell "this provider is down, try the next" from "asking
/// again immediately would just burn the next one's quota too".
///
/// Provider-agnostic on purpose: `LibrarySync` catches THIS, not any one
/// provider's exception type, which is what lets a second provider be added
/// without touching the fill path.
class MetadataException implements Exception {
  const MetadataException(
    this.message, {
    this.failure = MetadataFailure.service,
  });

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => 'MetadataException: $message';
}

/// One source of "what is this show" — AniList, Kitsu, MyAnimeList, …
///
/// The contract is deliberately tiny: two reads, both returning domain models.
/// Everything provider-specific — HTTP, JSON shape, query language, format
/// vocabulary — stays inside the implementation (seam #3 generalised).
///
/// Implementations MUST:
/// - report every id they know via [Series.externalIds], not just their own,
///   because that is what lets `ensureSeriesId` recognise a show another
///   provider already identified instead of minting a duplicate identity;
/// - normalise [Series.format] to the shared vocabulary rather than passing
///   their own through — it is rendered raw in the UI, so an un-normalised mix
///   would show `TV` beside `movie`;
/// - throw [MetadataException] for any failure, so the chain can fall through.
abstract class MetadataProvider {
  /// Stable identifier, and the value written to
  /// `series_external_ids.provider`. Also what the settings list persists, so
  /// it must not change once shipped.
  String get token;

  /// Shown in the settings source list.
  String get displayName;

  /// Which external-id space this source's OWN ids belong to — the value used
  /// in `series_external_ids.provider`.
  ///
  /// Usually the same as [token], but not always: Jikan and the official
  /// MyAnimeList API are two DIFFERENT sources (separate rows in the settings
  /// list, separate reliability, one needs a key) that both speak MAL ids. They
  /// therefore have distinct tokens and a shared namespace.
  String get idNamespace => token;

  /// True for a source too unreliable to build a library's metadata on. Such a
  /// source is never allowed to outrank one that isn't, whatever order the user
  /// saves — it is worth having when everything else is down, and not
  /// otherwise. Default false.
  bool get isFallbackOnly => false;

  /// True for a source the user must supply a client ID before it can be used.
  /// A static property of the source; whether a key has actually been entered
  /// is state, and lives in settings — see [isConfigured].
  bool get requiresClientId => false;

  /// Whether this provider can be used right now. False for one awaiting a
  /// client ID the user hasn't supplied — such a provider is SKIPPED by the
  /// chain rather than counted as a failure.
  ///
  /// Async because the answer lives in settings and can change while the app is
  /// running: paste a key and the very next lookup should use it, with no
  /// restart and no stale cached copy.
  Future<bool> isConfigured();

  /// Ranked-candidate search for a parsed title. Returns `[]` for a genuine
  /// no-match; throws [MetadataException] when the lookup could not be made.
  Future<List<Series>> searchCandidates(String title, {int perPage});

  /// Re-fetch known entries by THIS provider's own ids (the refresh backfill).
  /// Ids the provider doesn't recognise are simply absent from the result.
  Future<List<Series>> fetchByProviderIds(List<int> providerIds);
}
