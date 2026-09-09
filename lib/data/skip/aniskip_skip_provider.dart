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

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    final malId = lookup.malId;
    // No MAL id means nothing to ask WITH — not a failure, just no answer.
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

/// Skip-source tokens. Separate namespace from the metadata sources: the two
/// lists are ordered independently and a token only has to be unique within
/// its own family.
const String kAniSkipSource = 'aniskip';
const String kChaptersSource = 'chapters';
const String kAnimeSkipSource = 'animeskip';
const String kFingerprintSource = 'fingerprint';
