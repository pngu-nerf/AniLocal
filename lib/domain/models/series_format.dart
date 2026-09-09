/// The ONE format vocabulary, and the mapping into it from each source's own.
///
/// `Series.format` is rendered RAW in four places in the UI, so an
/// un-normalised mix would literally show `TV` next to `movie` in one library
/// once a second source starts answering.
///
/// The canonical tokens are AniList's, deliberately: every format already
/// cached was written by AniList, so choosing anything else would mean either
/// a migration or a library that displays two vocabularies during the changeover
/// — for zero benefit. Normalise at each provider's boundary, never in the UI.
const String kFormatTv = 'TV';
const String kFormatTvShort = 'TV_SHORT';
const String kFormatMovie = 'MOVIE';
const String kFormatSpecial = 'SPECIAL';
const String kFormatOva = 'OVA';
const String kFormatOna = 'ONA';
const String kFormatMusic = 'MUSIC';

/// Map a provider's raw format onto the canonical vocabulary.
///
/// An unrecognised value is UPPER-CASED and passed through rather than dropped:
/// a source inventing a format we've never seen should still show the user
/// something, and silently blanking the field would look like missing data.
/// This matters concretely — MAL's published enum omits values it actually
/// returns (`pv`, `cm`, `tv_special` are all live), so an exhaustive parser
/// here would throw on real data.
String? normalizeSeriesFormat(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return switch (trimmed.toUpperCase().replaceAll(' ', '_')) {
    'TV' => kFormatTv,
    'TV_SHORT' || 'TV_SHORTS' || 'SHORT' => kFormatTvShort,
    'MOVIE' || 'FILM' => kFormatMovie,
    'SPECIAL' || 'TV_SPECIAL' => kFormatSpecial,
    'OVA' => kFormatOva,
    'ONA' => kFormatOna,
    'MUSIC' => kFormatMusic,
    // MAL says 'unknown' where the others say nothing at all.
    'UNKNOWN' => null,
    final other => other,
  };
}
