/// Synthetic identity for a NOT-YET-IDENTIFIED ("pending") placeholder series.
///
/// A pending show has no AniList id yet, so the read path groups its files by
/// normalized parsed title and hands the UI a stable, NEGATIVE synthetic id —
/// negative so it can never collide with a real (positive) AniList id; the
/// read path branches on the sign to tell a placeholder from a matched series.
///
/// This id is a transient handle: it exists only while a show is unidentified.
/// The one place it can land in durable storage is `watch_state` (if you watch
/// a placeholder before it's identified) — and the fill path REKEYS those rows
/// from the synthetic id to the real AniList id the moment the file identifies
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
