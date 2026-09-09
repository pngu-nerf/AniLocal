import '../../domain/models/external_ids.dart';
import '../../domain/models/series.dart';
import '../crossmap/cross_map_store.dart';
import '../jikan/jikan_client.dart';
import 'metadata_provider.dart';

/// Jikan (MyAnimeList's community proxy) as a [MetadataProvider].
///
/// **Fallback only** — see [isFallbackOnly]. Also does one thing the other
/// adapters don't: Jikan publishes only MAL ids, so each answer is enriched
/// from the cross-map (MAL -> AniList) before it leaves here. Without that a
/// Jikan-identified show would mint a fresh identity even when AniList already
/// names it, and the library would carry two kinds of id for no reason.
class JikanMetadataProvider implements MetadataProvider {
  const JikanMetadataProvider(this.client, {this.crossMap});

  final JikanClient client;

  /// Supplies the AniList id Jikan can't. Optional: without it the answers
  /// still work, they just land on minted identities.
  final CrossMapStore? crossMap;

  @override
  String get token => kMalProvider;

  @override
  String get displayName => 'MyAnimeList (via Jikan)';

  @override
  bool get isConfigured => true; // no key, no account

  @override
  bool get isFallbackOnly => true;

  @override
  Future<List<Series>> searchCandidates(String title, {int perPage = 10}) =>
      _translate(() => client.searchCandidates(title, perPage: perPage));

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) =>
      _translate(() => client.fetchByIds(providerIds));

  Future<List<Series>> _translate(Future<List<Series>> Function() body) async {
    final List<Series> raw;
    try {
      raw = await body();
    } on JikanException catch (e) {
      throw MetadataException(e.message, failure: e.failure);
    }
    return _withAnilistIds(raw);
  }

  Future<List<Series>> _withAnilistIds(List<Series> series) async {
    final store = crossMap;
    if (store == null || series.isEmpty) return series;
    final map = await store.load();
    if (map.isEmpty) return series;
    return [
      for (final s in series)
        s.externalIds.mal == null
            ? s
            : _withAnilist(s, map.anilistForMal(s.externalIds.mal!)),
    ];
  }

  Series _withAnilist(Series s, int? anilistId) {
    if (anilistId == null) return s;
    return Series(
      seriesId: s.seriesId,
      externalIds: ExternalIds(
        anilist: anilistId,
        mal: s.externalIds.mal,
        kitsu: s.externalIds.kitsu,
        anidb: s.externalIds.anidb,
      ),
      titles: s.titles,
      format: s.format,
      episodeCount: s.episodeCount,
      coverImageRef: s.coverImageRef,
    );
  }
}
