import 'models/episode.dart';

/// The next episode to watch in ONE series' episode list, or null.
///
/// The rule, in one place: take the FURTHEST watched anchored position; the
/// episode at `anchored + 1` is next if it exists and is itself unwatched. A
/// series with nothing watched has no "next"; a series whose furthest-watched
/// episode is the last one you have is caught up. This is the same rule the
/// repository's `upNextBySeries` applies over the whole library, and the show
/// page applies over the list it already holds — they share this function so
/// the card and the page can never disagree about what is next.
Episode? nextToWatch(Iterable<Episode> episodes) {
  int? latestWatched;
  for (final e in episodes) {
    if (!e.watched) continue;
    if (latestWatched == null || e.anchoredNumber > latestWatched) {
      latestWatched = e.anchoredNumber;
    }
  }
  if (latestWatched == null) return null;
  for (final e in episodes) {
    if (e.anchoredNumber != latestWatched + 1) continue;
    return e.watched ? null : e;
  }
  return null;
}
