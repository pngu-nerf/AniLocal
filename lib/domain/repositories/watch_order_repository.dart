import '../models/episode.dart';
import '../models/next_result.dart';

/// The single source of "what's next" (the "Up Next" feature). Every caller —
/// player auto-advance and the library "Next: Ep N" — routes through here;
/// none computes "next" itself. Cache-backed (seam #2); never touches the
/// network.
abstract interface class WatchOrderRepository {
  /// What plays after [current]. Today: the next anchored episode in the SAME
  /// series, else [NoNextEpisode]. The [NoNextEpisode] at a season boundary is
  /// the correct end-of-season answer now AND the deliberate seam where
  /// cross-season slots in later (follow the AniList SEQUEL relation here) —
  /// not unfinished work.
  Future<NextResult> nextEpisode(Episode current);

  /// The next episode to watch, per series the user has STARTED (watched ≥1):
  /// the within-season episode after their furthest-watched one. Omits series
  /// not started, or caught up (resolver returns [NoNextEpisode]). Keyed by the
  /// series' AniList id — powers the per-series "Next: Ep N" affordance.
  Future<Map<int, Episode>> upNextBySeries();
}
