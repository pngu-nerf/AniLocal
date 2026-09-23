import 'models/airing_status.dart';
import 'models/series.dart';

/// How long after the finale a show still says "the last episode is out"
/// when the library does not have it. After that the show is simply finished.
const Duration kAiringGrace = Duration(days: 7);

/// What the episode-count line says about a show's broadcast right now.
/// Pure: computed from the cached [Series] and the clock at render time, so
/// "in 3 days" is always measured against the computer's clock, never stored.
sealed class AiringState {
  const AiringState();
}

/// An episode has aired that the library does not have — the flag.
class NewEpisode extends AiringState {
  const NewEpisode(this.episode, {this.airedAt});

  /// The highest aired episode number not in the library.
  final int episode;

  /// When it aired, if the source gave a schedule (AniList does).
  final DateTime? airedAt;
}

/// The show is airing and the library is caught up — the quiet note.
class Airing extends AiringState {
  const Airing({this.nextEpisode, this.nextAt});

  /// The next episode number and its air time, when the source knows them.
  final int? nextEpisode;
  final DateTime? nextAt;
}

/// The highest episode number that has aired by [now], or null when the
/// source gave no schedule. The check that fetched `nextAiringAt` may be days
/// old, so the CLOCK decides whether that next episode has aired since:
/// once its time has passed it counts as out, even before the next scan.
int? airedThroughFor(Series s, DateTime now) {
  switch (s.airingStatus) {
    case AiringStatus.releasing:
      final next = s.nextAiringEpisode;
      if (next == null) return null;
      final at = s.nextAiringAt;
      return at != null && !at.isAfter(now) ? next : next - 1;
    case AiringStatus.finished:
      return s.episodeCount;
    case AiringStatus.notYetReleased:
      return 0;
    case AiringStatus.unknown:
      return null;
  }
}

/// The indicator for [series] given the highest episode number the library
/// holds ([highestPresent], 0 when none). Null means: show nothing — not
/// airing, muted for this show, or finished for longer than [kAiringGrace].
AiringState? airingStateFor(
  Series series, {
  required int highestPresent,
  required DateTime now,
}) {
  if (series.airingHidden) return null;
  switch (series.airingStatus) {
    case AiringStatus.releasing:
      final aired = airedThroughFor(series, now);
      if (aired != null && aired > highestPresent) {
        return NewEpisode(
          aired,
          airedAt: aired == series.nextAiringEpisode
              ? series.nextAiringAt
              : null,
        );
      }
      // Caught up. If the scheduled episode's time has passed, the "next" we
      // know of is already out and the real next is unknown until a scan.
      final nextAt = series.nextAiringAt;
      final scheduledIsOut = nextAt != null && !nextAt.isAfter(now);
      return Airing(
        nextEpisode: scheduledIsOut ? null : series.nextAiringEpisode,
        nextAt: scheduledIsOut ? null : nextAt,
      );
    case AiringStatus.finished:
      final end = series.endDate;
      final total = series.episodeCount;
      if (end == null || total == null) return null;
      final since = now.difference(end);
      if (since > kAiringGrace) return null;
      return total > highestPresent ? NewEpisode(total, airedAt: end) : null;
    case AiringStatus.notYetReleased:
    case AiringStatus.unknown:
      return null;
  }
}
