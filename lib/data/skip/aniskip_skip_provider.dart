import '../../domain/models/skip_range.dart';
import '../aniskip/aniskip_client.dart';
import 'skip_provider.dart';

/// AniSkip as a [SkipProvider].
///
/// Thin adapter, like the metadata ones: all HTTP stays in `lib/data/aniskip`.
/// Keyed by MAL id, so an episode whose series has none is a clean null rather
/// than a failure — that is ordinary, not a fault.
class AniSkipSkipProvider implements SkipProvider {
  const AniSkipSkipProvider(this.client);

  final AniSkipClient client;

  @override
  String get token => kAniSkipSource;

  @override
  String get displayName => 'AniSkip';

  @override
  bool get requiresClientId => false;

  @override
  String? get setupUrl => null;

  @override
  String? get setupInstructions => null;

  @override
  Future<bool> isConfigured() async => true; // public, no key

  /// AniSkip is keyed by MAL id, so without one there is nothing to ask WITH.
  /// Deliberately "could not try" rather than "no data": the id frequently
  /// arrives later from the cross-map, and recording an answer now would stop
  /// this source ever being asked again.
  @override
  bool canAnswer(SkipLookup lookup) => lookup.malId != null;

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    final malId = lookup.malId;
    if (malId == null) return null;
    try {
      return await client.fetchSkips(
        malId,
        lookup.episode,
        episodeLengthSeconds: lookup.episodeLength?.inSeconds ?? 0,
      );
    } on AniSkipException catch (e) {
      throw SkipException(e.message, failure: e.failure);
    }
  }
}
