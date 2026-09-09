import '../../domain/models/metadata_failure.dart';
import '../../domain/models/skip_range.dart';

/// Skip-source tokens. A SEPARATE namespace from the metadata sources: the two
/// lists are ordered independently, so a token only has to be unique within its
/// own family. Lives here rather than beside any one provider, because the
/// family owns the vocabulary.
const String kAniSkipSource = 'aniskip';
const String kChaptersSource = 'chapters';
const String kAnimeSkipSource = 'animeskip';
const String kFingerprintSource = 'fingerprint';

/// Thrown when a skip source cannot answer. Mirrors `MetadataException` so the
/// two families report failures the same way and the UI copy is shared.
class SkipException implements Exception {
  const SkipException(this.message, {this.failure = MetadataFailure.service});

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => 'SkipException: $message';
}

/// Everything a skip source might need to answer for ONE episode.
///
/// A single request shape for every source, because they key off different
/// things and threading four signatures through the fill path would be worse:
/// AniSkip needs the MAL id and episode number, chapters need the FILE, and
/// fingerprinting needs the file plus its siblings. A source ignores what it
/// doesn't use and returns null when it has nothing to go on.
class SkipLookup {
  const SkipLookup({
    required this.seriesId,
    required this.episode,
    this.malId,
    this.filePath,
    this.siblingPaths = const [],
    this.episodeLength,
  });

  /// AniLocal's own identity for the show (see `series_identity.dart`).
  final int seriesId;

  /// Anchored episode number, the other half of episode identity.
  final int episode;

  /// For sources keyed by MyAnimeList — AniSkip, and Anime Skip.
  final int? malId;

  /// For LOCAL sources: the file this episode actually plays from.
  final String? filePath;

  /// Other episodes of the same series, for a source that finds the OP by
  /// looking for what repeats across them (fingerprinting).
  final List<String> siblingPaths;

  /// Improves AniSkip's matching when known.
  final Duration? episodeLength;
}

/// One source of "where is the OP/ED".
///
/// Deliberately a SEPARATE family from `MetadataProvider`: that answers "what
/// is this show", this answers "where is the opening". They fail independently,
/// have different sources, and the user orders them separately — blurring them
/// into one list would be worse than the small duplication of having two.
///
/// Implementations MUST return null for "I have no data for this episode" and
/// throw [SkipException] only for a genuine failure. Partial coverage is
/// NORMAL here — far more so than for metadata — so a null must never be
/// treated as the source being down.
abstract interface class SkipProvider {
  /// Stable identifier; also what the user's saved order persists.
  String get token;

  /// Shown in the settings source list.
  String get displayName;

  /// True for a source needing a client ID before it can be used. Reuses the
  /// same per-source key storage the metadata family added.
  bool get requiresClientId => false;

  String? get setupUrl => null;
  String? get setupInstructions => null;

  /// Whether this source can be used right now. Async and read fresh, so
  /// pasting a key takes effect without a restart.
  Future<bool> isConfigured();

  /// Windows for one episode, or null when this source simply has none.
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup);
}
