import '../../data/paths.dart' show basenameOf;
import '../../domain/missing_episodes.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/episode_list_row.dart';
import '../../domain/models/episode_slot.dart';

// The show page's list logic, pure: what matches the live search and which
// rows the page lists. Its own file so it is tested without a widget and the
// page file holds the page.

/// Whether an episode matches the live episode-search [query]. Matches on:
///  - the episode [number] by PREFIX, so it narrows as you type ("4" → 4, 40–49,
///    400–499…; "14" → 14, 140–149) — NOT arbitrary substring (so "7" never
///    matches 47, and "41" never matches 141), and
///  - the [fileName] (a present episode's filename basename) by case-insensitive
///    SUBSTRING, so text from the filename — resolution, group, etc. — is
///    searchable (a missing/ghost episode has no file, so it matches by number
///    only).
///
/// A blank query matches everything (clearing restores the full list). The
/// synthetic per-episode title is deliberately NOT matched: it is always the
/// literal `"Episode N"` (real titles aren't cached), so matching it added only
/// noise (e.g. "episode" matching everything). Pure (UI-layer, filters an
/// already-loaded list) so it's unit-testable — the episode-list analogue of
/// the homepage's `seriesMatchesQuery`.
bool episodeMatchesQuery({
  required int number,
  String? fileName,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if ('$number'.startsWith(q)) return true;
  return fileName != null && fileName.toLowerCase().contains(q);
}

/// The rows the show page lists for [episodes], given the hidden set, the
/// show's episode count, whether the missing-episodes feature is on, and the
/// live search. Pure: the grouping and filtering were inlined in `build`,
/// where they re-ran on every rebuild and could not be tested.
List<EpisodeListRow> episodeRowsFor({
  required List<Episode> episodes,
  required Set<int> hidden,
  required int? episodeCount,
  required bool showMissing,
  required String query,
  List<EpisodeSlot>? slots,
}) {
  final q = query.trim().toLowerCase();
  if (!showMissing) {
    return [
      for (final e in episodes)
        if (episodeMatchesQuery(
          number: e.number,
          fileName: basenameOf(e.fileRef),
          query: q,
        ))
          PresentRow(e),
    ];
  }
  // [slots] may be supplied by a caller that already computed (and memoised)
  // them; otherwise derive them here — same function, same result.
  slots ??= computeEpisodeSlots(
    present: episodes,
    hidden: hidden,
    episodeCount: episodeCount,
  );
  if (q.isEmpty) return groupIntoRows(slots);
  // Filter present + ghost slots (dropping hidden, which never show here) and
  // re-group the survivors — so a filtered run of missing episodes still
  // bundles/singles per the existing 2+-consecutive rule.
  return groupIntoRows([
    for (final s in slots)
      if (s.status != EpisodeStatus.hidden &&
          episodeMatchesQuery(
            number: s.episode?.number ?? s.number,
            // A ghost (missing) slot has no file → number-only match.
            fileName: s.episode == null ? null : basenameOf(s.episode!.fileRef),
            query: q,
          ))
        s,
  ]);
}
