import 'models/episode.dart';
import 'models/episode_list_row.dart';
import 'models/episode_slot.dart';

/// Pure, side-effect-free logic for the missing-episodes feature. The DATA the
/// UI feeds in — present episodes, the hidden set, the AniList count — comes
/// from the repository; everything here is recomputed live on every read, so
/// nothing about grouping or counts is ever persisted.

/// Compute the per-episode truth for one series over its detection range.
///
/// - [present]: the in-library (logical) episodes. Their [Episode.anchoredNumber]
///   is the AniList-faithful position and the identity everything keys on.
/// - [hidden]: anchored positions the user has hidden.
/// - [episodeCount]: M, the AniList episode count, or null if unknown.
///
/// Rules (robust to messy/non-contiguous/non-integer numbering — see below):
///  - When M is known, the range is 1..M: every absent position in it is
///    missing (unless hidden). Present episodes beyond M still appear (they're
///    the separate "+X" concept) but are never gap-detected.
///  - When M is unknown, ONLY interior gaps are detected — absent positions
///    strictly between the lowest and highest OWNED (present) standard episode.
///    Never invents episodes beyond the highest owned.
///  - Only standard positions (>= 1) are gap-detected. Specials / non-standard
///    positions (<= 0) are surfaced as present slots but never flagged missing,
///    so we never conjure a phantom "missing special".
List<EpisodeSlot> computeEpisodeSlots({
  required List<Episode> present,
  required Set<int> hidden,
  required int? episodeCount,
}) {
  final byPosition = <int, Episode>{
    for (final e in present) e.anchoredNumber: e,
  };
  final standardPresent = byPosition.keys.where((p) => p >= 1).toList()..sort();

  // The window over which an absent position counts as "missing".
  int? low;
  int? high;
  final m = episodeCount;
  if (m != null && m >= 1) {
    low = 1;
    high = m;
  } else if (standardPresent.isNotEmpty) {
    // Interior gaps only: bounded by what we actually own.
    low = standardPresent.first;
    high = standardPresent.last;
  }

  // Every position we will emit a slot for: all present (incl. specials and
  // out-of-range), all hidden, and the whole missing window.
  final positions = <int>{...byPosition.keys, ...hidden};
  if (low != null && high != null) {
    for (var p = low; p <= high; p++) {
      positions.add(p);
    }
  }

  final ordered = positions.toList()..sort();
  final slots = <EpisodeSlot>[];
  for (final p in ordered) {
    if (hidden.contains(p)) {
      // Hidden wins over present: a position the user hid stays out of the list
      // even if a file later appears for it (unhide brings it back).
      slots.add(EpisodeSlot(number: p, status: EpisodeStatus.hidden));
    } else if (byPosition.containsKey(p)) {
      slots.add(
        EpisodeSlot(
          number: p,
          status: EpisodeStatus.present,
          episode: byPosition[p],
        ),
      );
    } else {
      // Absent & not hidden. Missing only within the standard detection window;
      // an absent position outside it (e.g. above M, or below min when M is
      // unknown) is simply not emitted.
      final inWindow =
          low != null && high != null && p >= low && p <= high && p >= 1;
      if (inWindow) {
        slots.add(EpisodeSlot(number: p, status: EpisodeStatus.missing));
      }
    }
  }
  return slots;
}

/// Group per-episode [slots] into display rows. A maximal run of 2+ CONSECUTIVE
/// missing positions (contiguous integers) becomes one [MissingBundleRow];
/// isolated missing positions become [MissingSingleRow]; present episodes are
/// [PresentRow]. Hidden slots are dropped from the list AND break a run — so a
/// bundle never spans a hidden (or present) position, keeping the bundle's
/// "everything between" promise honest.
List<EpisodeListRow> groupIntoRows(List<EpisodeSlot> slots) {
  final rows = <EpisodeListRow>[];
  var run = <int>[];

  void flushRun() {
    if (run.isEmpty) return;
    rows.add(
      run.length == 1
          ? MissingSingleRow(run.first)
          : MissingBundleRow(numbers: List<int>.of(run)),
    );
    run = [];
  }

  for (final s in slots) {
    switch (s.status) {
      case EpisodeStatus.present:
        flushRun();
        rows.add(PresentRow(s.episode!));
      case EpisodeStatus.hidden:
        flushRun(); // hidden is a break and is not itself shown
      case EpisodeStatus.missing:
        // Only contiguous integers stay in one run.
        if (run.isNotEmpty && s.number != run.last + 1) flushRun();
        run.add(s.number);
    }
  }
  flushRun();
  return rows;
}

/// The downloaded-episode tally for the "⬇N of M +X" indicator, computed
/// consistently everywhere from the same per-episode truth. Hidden positions
/// within 1..M are excluded from the denominator (they no longer count toward
/// completeness), so hiding a missing episode moves "11 of 12" → "11 of 11".
class DownloadTally {
  const DownloadTally({
    required this.inRange,
    required this.outOfRange,
    required this.total,
  });

  /// Present episodes whose position is within 1..M (or all present when M is
  /// unknown).
  final int inRange;

  /// Present episodes outside 1..M (position > M, or unanchored/special) — the
  /// "+X" extras.
  final int outOfRange;

  /// The completeness denominator M, reduced by any hidden in-range positions;
  /// null when the AniList count is unknown (indicator then shows just "⬇N").
  final int? total;
}

DownloadTally computeDownloadTally(List<EpisodeSlot> slots, int? episodeCount) {
  final m = episodeCount;
  var inRange = 0;
  var outOfRange = 0;
  var hiddenInRange = 0;
  for (final s in slots) {
    switch (s.status) {
      case EpisodeStatus.present:
        if (m == null || (s.number >= 1 && s.number <= m)) {
          inRange++;
        } else {
          outOfRange++;
        }
      case EpisodeStatus.hidden:
        if (m != null && s.number >= 1 && s.number <= m) hiddenInRange++;
      case EpisodeStatus.missing:
        break;
    }
  }
  return DownloadTally(
    inRange: inRange,
    outOfRange: outOfRange,
    total: m == null ? null : m - hiddenInRange,
  );
}
