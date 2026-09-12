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
  Future<bool> canAnswer(SkipLookup lookup) async => lookup.malId != null;

  @override
  bool get readsFile => false;

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    final malId = lookup.malId;
    if (malId == null) return null;
    try {
      // Episode length is sent as 0 ("unknown"): the fill path has no
      // duration without opening the container, which only the chapters
      // source does. AniSkip uses the length to filter submissions made
      // against a different release; without it, it returns them all.
      return await client.fetchSkips(malId, lookup.episode);
    } on AniSkipException catch (e) {
      throw SkipException(e.message, failure: e.failure);
    }
  }
}
