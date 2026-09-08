/// The one place the series-id space is defined.
///
/// `series_id` is an OPAQUE LOCAL SURROGATE, not any provider's id. It has to
/// be: metadata sources are user-reorderable, so keying user data by "whatever
/// the current top source calls this show" would strand watch state on every
/// reorder — and 4,655 anime on Kitsu have no AniList id at all, so no single
/// provider's id could serve as the key.
///
/// Three disjoint bands, and code should ask via the predicates below rather
/// than re-deriving the rule (it used to be a bare `< 0` in three places):
///
/// ```
/// id <  0                        PLACEHOLDER      not yet identified
/// 0 <  id < kMintedSeriesIdBase  PROVIDER-SEEDED  == an AniList id (v14 invariant)
/// id >= kMintedSeriesIdBase      MINTED           no AniList id; see series_external_ids
/// ```
library;

/// Where minted ids start. Above any conceivable AniList id (they are ~6
/// digits) and far below 2^63, so both bands have enormous headroom. SQLite
/// INTEGER and Dart `int` are 64-bit signed, so the size costs nothing.
///
/// Minted ids exist for shows a provider knows but AniList does not. The
/// negative range could not be reused: [placeholderStableHash] masks to 31
/// bits, so placeholders already occupy it densely.
const int kMintedSeriesIdBase = 1 << 40;

/// A not-yet-identified show, grouped by parsed title. Transient — see
/// [placeholderSeriesId].
bool isPlaceholderSeriesId(int id) => id < 0;

/// An id seeded from a provider. By the v14 migration's invariant every such
/// id in an existing cache IS the AniList id it was before the rename.
bool isProviderSeededSeriesId(int id) => id > 0 && id < kMintedSeriesIdBase;

/// An id AniLocal minted itself because no AniList id existed. Its provider
/// ids live in `series_external_ids`.
bool isMintedSeriesId(int id) => id >= kMintedSeriesIdBase;

/// Synthetic identity for a NOT-YET-IDENTIFIED ("pending") placeholder series.
///
/// A pending show has no provider id yet, so the read path groups its files by
/// normalized parsed title and hands the UI a stable, NEGATIVE synthetic id —
/// negative so it can never collide with a seeded or minted id; the read path
/// branches on the band to tell a placeholder from an identified series.
///
/// This id is a transient handle: it exists only while a show is unidentified.
/// The one place it can land in durable storage is `watch_state` (if you watch
/// a placeholder before it's identified) — and the fill path REKEYS those rows
/// from the synthetic id to the real series id the moment the file identifies
/// (see [CacheDatabase.applySync]'s `promotions`), so it never SURVIVES
/// identification. Source pins refuse a pending episode outright, so the
/// synthetic id never reaches `source_overrides`. Match overrides are keyed by
/// file fingerprint and store the real target id, never this one.
int placeholderSeriesId(String normalizedTitle) =>
    -1 - placeholderStableHash(normalizedTitle);

/// Deterministic FNV-1a hash masked to a positive 31-bit int. Deterministic
/// across runs so a placeholder keeps its identity (and any watch progress)
/// until it's upgraded.
int placeholderStableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}
