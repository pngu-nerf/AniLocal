import '../../domain/models/external_ids.dart';
import '../../domain/models/series.dart';
import '../kitsu/kitsu_client.dart';
import 'metadata_provider.dart';

/// Kitsu as a [MetadataProvider].
///
/// Thin, like the AniList adapter: all HTTP and JSON:API handling stays in
/// `lib/data/kitsu`. This presents it through the provider contract and
/// translates its exception type.
class KitsuMetadataProvider implements MetadataProvider {
  const KitsuMetadataProvider(this.client);

  final KitsuClient client;

  @override
  String get token => kKitsuProvider;

  @override
  String get displayName => 'Kitsu';

  @override
  String get idNamespace => token;

  @override
  bool get requiresClientId => false;

  @override
  Future<bool> isConfigured() async => true; // public reads, no key

  @override
  bool get isFallbackOnly => false;

  @override
  Future<List<Series>> searchCandidates(String title, {int perPage = 10}) =>
      _translate(() => client.searchCandidates(title, perPage: perPage));

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) =>
      _translate(() => client.fetchByIds(providerIds));

  Future<T> _translate<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on KitsuException catch (e) {
      throw MetadataException(e.message, failure: e.failure);
    }
  }
}
