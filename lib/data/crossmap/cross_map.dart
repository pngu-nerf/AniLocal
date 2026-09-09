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
  CrossMap(this._byAnilistId);

  /// Nothing known. Every lookup returns null, so callers degrade to exactly
  /// the behaviour they had before the map existed — never worse.
  static final CrossMap empty = CrossMap(const <int, CrossMapEntry>{});

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

  /// MAL id -> AniList id. Built on first use, because only a MAL-only source
  /// (Jikan) needs it and most runs never will.
  Map<int, int>? _anilistByMal;

  /// The AniList id for a show known only by its MAL id, or null.
  ///
  /// This is what lets a MAL-sourced answer land on the SEEDED identity instead
  /// of minting a new one — the same job Kitsu's inline mappings do for itself.
  int? anilistForMal(int malId) {
    final index = _anilistByMal ??= {
      for (final e in _byAnilistId.entries)
        if (e.value.malId != null) e.value.malId!: e.key,
    };
    return index[malId];
  }
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
