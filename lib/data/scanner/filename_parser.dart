/// The result of parsing a release filename into its meaningful parts.
///
/// Internal to `lib/data/scanner` — does not cross into the UI (the relevant
/// fields are surfaced via the domain `IdentifiedEpisode`).
class ParsedFilename {
  const ParsedFilename({
    required this.rawName,
    required this.title,
    this.episodeNumber,
    this.seasonNumber,
    this.releaseGroup,
  });

  /// Original filename (with extension), for reference/debugging.
  final String rawName;

  /// Cleaned title text to search AniList with.
  final String title;

  /// Episode number, if found (null for movies/specials or unparseable).
  final int? episodeNumber;

  /// Season number from an `S02`/`Season 2` marker, if present.
  final int? seasonNumber;

  /// Release group from a leading `[Group]` tag, if present.
  final String? releaseGroup;
}

/// Seam #4: identification lives behind this one interface so the parser is
/// swappable (today a heuristic, tomorrow a better port) without touching
/// anything else. Pure and network-free — matching to AniList happens elsewhere.
abstract interface class FilenameParser {
  /// Parse a single video [filename] (basename, extension included) into parts.
  ParsedFilename parse(String filename);
}
