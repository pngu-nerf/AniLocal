import '../../domain/models/external_ids.dart';
import '../../domain/models/series.dart';
import '../mal/mal_client.dart';
import 'metadata_provider.dart';

/// The official MyAnimeList API as a [MetadataProvider].
///
/// Ships DISABLED and stays inert until the user supplies their own client ID.
/// AniLocal deliberately embeds no key: MAL's API agreement §2(a) forbids
/// sharing a client ID with third parties and §3(c) requires keeping it
/// secure, neither of which is possible for a string inside a binary anyone can
/// download. A shipped key would also be a single point of failure worse than
/// any outage here — revoke it once and every install breaks at the same
/// moment, permanently.
class MalMetadataProvider implements MetadataProvider {
  const MalMetadataProvider(this.client, {required this.loadClientId});

  final MalClient client;

  /// Read fresh, so adding or clearing the key takes effect on the next lookup.
  final Future<String?> Function() loadClientId;

  @override
  String get token => kMyAnimeListProvider;

  @override
  // Its own ids ARE MAL ids — the same space Jikan reports into.
  String get idNamespace => kMalProvider;

  @override
  String get displayName => 'MyAnimeList';

  @override
  bool get requiresClientId => true;

  @override
  bool get isFallbackOnly => false; // reliable once configured

  @override
  Future<bool> isConfigured() async {
    final id = await loadClientId();
    return id != null && id.isNotEmpty;
  }

  @override
  Future<List<Series>> searchCandidates(String title, {int perPage = 10}) =>
      _translate(() => client.searchCandidates(title, perPage: perPage));

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) =>
      _translate(() => client.fetchByIds(providerIds));

  Future<T> _translate<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on MalException catch (e) {
      throw MetadataException(e.message, failure: e.failure);
    }
  }
}
