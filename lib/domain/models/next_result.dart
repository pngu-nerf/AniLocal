import 'episode.dart';

/// The result of resolving "what plays after this episode" — the return of the
/// single watch-order resolver. A dedicated type (not a bare `Episode?`) makes
/// the season-boundary case explicit and gives callers one thing to branch on.
///
/// Today the resolver is WITHIN-SEASON only: the next anchored episode in the
/// same series, or [NoNextEpisode] when there isn't one. [NoNextEpisode] is the
/// correct end-of-season answer now AND the deliberate seam where cross-season
/// slots in later — the planned extension turns "last episode → NoNextEpisode"
/// into "…else episode 1 of the AniList SEQUEL." That change is one function;
/// all callers already route through here, so none of them change.
sealed class NextResult {
  const NextResult();
}

/// There is a next episode to play.
final class NextEpisode extends NextResult {
  const NextEpisode(this.episode);
  final Episode episode;
}

/// No next episode in the library — also the season-boundary answer today
/// (the seam for the future cross-season extension).
final class NoNextEpisode extends NextResult {
  const NoNextEpisode();
}
