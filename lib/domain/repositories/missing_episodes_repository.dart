/// The UI's read/write path for user-hidden missing episodes. Backed by the
/// local cache (seam #2); the hidden state is persisted user data, sacred across
/// rescans (seam #5 — the fill path has no writer for it). Keyed by episode
/// identity: a series + an anchored episode position.
abstract interface class MissingEpisodesRepository {
  /// The anchored positions the user has hidden for [seriesId] (empty set when
  /// none). Used to build the per-episode truth and the Hidden tab.
  Future<Set<int>> hiddenEpisodes(int seriesId);

  /// All hidden positions across the library, keyed by series id — one read for
  /// the grid's per-series completeness counts (a series absent from the map has
  /// nothing hidden).
  Future<Map<int, Set<int>>> allHiddenEpisodes();

  /// Hide the given anchored positions for [seriesId] (per-episode, even when
  /// the action targeted a whole bundle). Idempotent.
  Future<void> hideEpisodes(int seriesId, List<int> episodes);

  /// Unhide (restore) the given anchored positions for [seriesId].
  Future<void> unhideEpisodes(int seriesId, List<int> episodes);
}
