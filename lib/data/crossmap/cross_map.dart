/// A cross-database id map: one show's id on AniList → its id elsewhere.
///
/// Exists because ids are the ONE thing every anime database agrees to
/// disagree about, and AniLocal needs a MAL id to ask AniSkip for OP/ED
/// windows. That id used to come only from AniList's `idMal` — so when AniList
/// is unreachable, a newly-identified show has no MAL id and silently loses
/// auto-skip. This map supplies it offline instead.
///
/// Purely a lookup table: no titles, no art, no network. [CrossMapStore] owns
/// fetching and caching; this class only answers questions.
class CrossMap {
  const CrossMap(this._byAnilistId);

  /// Nothing known. Every lookup returns null, so callers degrade to exactly
  /// the behaviour they had before the map existed — never worse.
  static const CrossMap empty = CrossMap(<int, CrossMapEntry>{});

  final Map<int, CrossMapEntry> _byAnilistId;

  /// MyAnimeList id for [anilistId], or null when unknown.
  int? malFor(int anilistId) => _byAnilistId[anilistId]?.malId;

  /// Kitsu id for [anilistId], or null when unknown.
  int? kitsuFor(int anilistId) => _byAnilistId[anilistId]?.kitsuId;

  /// How many AniList entries the map knows. 0 means "no map available" —
  /// the offline/first-run state, and not an error.
  int get length => _byAnilistId.length;

  bool get isEmpty => _byAnilistId.isEmpty;

  /// Every AniList id the map knows, for serialising the derived cache.
  Iterable<int> get anilistIds => _byAnilistId.keys;
}

/// The ids AniLocal actually consumes. Deliberately NOT the source record's
/// full field set (which also carries tvdb/tmdb/imdb/anidb and more): storing
/// only what we read keeps the derived cache small and stops the map from
/// quietly becoming a second metadata store.
class CrossMapEntry {
  const CrossMapEntry({this.malId, this.kitsuId});

  final int? malId;
  final int? kitsuId;
}
