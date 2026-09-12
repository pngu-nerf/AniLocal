/// What the READ path needs to turn stored skip answers into windows.
///
/// Three live reads, one object, passed to `DriftLibraryRepository` at
/// construction and REQUIRED there. This replaced three public mutable
/// nullable function fields that the composition root set after the fact —
/// which existed only because the settings repository used to be built FROM
/// the library repository, so neither could be the other's constructor
/// argument. That cycle is gone; a repository without a view no longer
/// compiles, so it can no longer silently degrade to "no source is known".
///
/// Read fresh per query, never snapshotted: changing any of these takes
/// effect on the next read instead of needing a rescan.
class SkipViewSource {
  const SkipViewSource({
    required this.minLength,
    required this.activeSources,
    required this.knownSources,
    required this.corroborate,
  });

  /// A fixed view, for callers (tests, tools) that are not about skips.
  /// [known] defaults to [order]: every listed source is a shipped one.
  factory SkipViewSource.fixed({
    required List<String> order,
    List<String>? known,
    Duration floor = Duration.zero,
    bool corroborate = false,
  }) => SkipViewSource(
    minLength: () async => floor,
    activeSources: () async => order,
    knownSources: () async => known ?? order,
    corroborate: () async => corroborate,
  );

  /// The user's floor on how short a skip may be (0 = off).
  final Future<Duration> Function() minLength;

  /// The ENABLED source tokens in the user's priority order. The composition
  /// root supplies it because only it knows which sources this build ships;
  /// the repository must not see a provider (seam #1).
  final Future<List<String>> Function() activeSources;

  /// EVERY source token this build ships, enabled or not. A known source that
  /// is absent from [activeSources] is one the user switched OFF, and its
  /// stored answers are ignored outright — distinct from an answer whose
  /// source this build does not know (legacy, or a retired source), which is
  /// a last resort. Without this list the two cases collapsed and a disabled
  /// source's windows kept being used.
  final Future<List<String>> Function() knownSources;

  /// Whether the read path cross-checks sources against each other.
  final Future<bool> Function() corroborate;
}
