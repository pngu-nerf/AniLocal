import '../../domain/models/external_ids.dart';
import '../../domain/models/series.dart';
import '../anilist/anilist_client.dart';
import 'metadata_provider.dart';

/// AniList as a [MetadataProvider].
///
/// A thin adapter on purpose: every HTTP call, GraphQL query and JSON shape
/// stays inside `lib/data/anilist` (seam #3). All this does is present that
/// module through the provider contract and translate its exception type, so
/// the fill path can catch one provider-agnostic error.
class AniListMetadataProvider implements MetadataProvider {
  const AniListMetadataProvider(this.client, {this.formatsIn});

  final AniListClient client;

  /// AniList's own `MediaFormat` allow-list (cuts MUSIC false-positives).
  /// Provider-specific vocabulary, so it belongs here rather than being
  /// threaded through the matcher.
  final List<String>? formatsIn;

  @override
  String get token => kAnilistProvider;

  @override
  String get displayName => 'AniList';

  @override
  bool get isConfigured => true; // public reads, no key

  @override
  bool get isFallbackOnly => false;

  @override
  Future<List<Series>> searchCandidates(String title, {int perPage = 10}) =>
      _translate(
        () => client.searchSeriesCandidates(
          title,
          formatsIn: formatsIn,
          perPage: perPage,
        ),
      );

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) =>
      _translate(() => client.fetchSeriesByIds(providerIds));

  /// AniList's exception becomes the shared one, preserving the failure kind so
  /// the UI still says whose end the fault is on.
  Future<T> _translate<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AniListException catch (e) {
      throw MetadataException(e.message, failure: e.failure);
    }
  }
}
