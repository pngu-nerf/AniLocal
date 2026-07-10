/// The UI's read/write path for user-hidden missing episodes. Backed by the
/// local cache (seam #2); the hidden state is persisted user data, sacred across
/// rescans (seam #5 — the fill path has no writer for it). Keyed by episode
/// identity: an AniList entry + an anchored episode position.
abstract interface class MissingEpisodesRepository {
  /// The anchored positions the user has hidden for [anilistId] (empty set when
  /// none). Used to build the per-episode truth and the Hidden tab.
  Future<Set<int>> hiddenEpisodes(int anilistId);

  /// All hidden positions across the library, keyed by AniList id — one read for
  /// the grid's per-series completeness counts (a series absent from the map has
  /// nothing hidden).
  Future<Map<int, Set<int>>> allHiddenEpisodes();

  /// Hide the given anchored positions for [anilistId] (per-episode, even when
  /// the action targeted a whole bundle). Idempotent.
  Future<void> hideEpisodes(int anilistId, List<int> episodes);

  /// Unhide (restore) the given anchored positions for [anilistId].
  Future<void> unhideEpisodes(int anilistId, List<int> episodes);
}
