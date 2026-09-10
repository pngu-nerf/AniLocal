import 'models/skip_range.dart';

/// One chapter boundary read from a media file.
///
/// Containers store chapter STARTS; a chapter's end is the next one's start,
/// and the last one ends at the file's duration. [ChapterSpan] is the resolved
/// form after that arithmetic.
class ChapterMark {
  const ChapterMark({required this.start, this.title});

  final Duration start;

  /// Almost always empty in practice — across a 285-file library only THREE
  /// chapters carried one — which is why OP/ED is inferred from duration
  /// rather than read from a label.
  final String? title;
}

/// A resolved chapter: start, and the end derived from the next start (or the
/// file duration, for the last one).
class ChapterSpan {
  const ChapterSpan(this.start, this.end);

  final Duration start;
  final Duration end;

  Duration get length => end - start;
}

/// Openings and endings are ~90 seconds by long-standing convention, and the
/// data agrees: across the reference library, 197 chapter spans fell in the
/// 80–100s band with a mode of exactly 90s (then 91s, then 93s).
///
/// The band is kept TIGHT on purpose. Widening it to catch an unusual OP would
/// start catching ordinary scenes, and the two errors are not equal: failing to
/// offer a skip is a minor annoyance, while skipping 90 seconds of actual
/// episode is the thing users cannot forgive.
const Duration kOpeningMinLength = Duration(seconds: 85);
const Duration kOpeningMaxLength = Duration(seconds: 100);

/// Resolve chapter marks into spans, using [duration] to close the last one.
List<ChapterSpan> chapterSpans(List<ChapterMark> marks, Duration duration) {
  if (marks.isEmpty) return const [];
  final sorted = [...marks]..sort((a, b) => a.start.compareTo(b.start));
  final spans = <ChapterSpan>[];
  for (var i = 0; i < sorted.length; i++) {
    final start = sorted[i].start;
    final end = i + 1 < sorted.length ? sorted[i + 1].start : duration;
    if (end > start) spans.add(ChapterSpan(start, end));
  }
  return spans;
}

/// Infer the OP/ED windows from chapter spans, or null when nothing qualifies.
///
/// **Inferred, not read.** Release groups mark chapter boundaries but almost
/// never label them, so this recognises an opening by its LENGTH — never its
/// position. Position genuinely varies: in the reference library episode 1
/// opens cold with the OP at 498s while episodes 2 and 3 start it at 0s, so any
/// rule keyed on "the first chapter" would be wrong immediately.
///
/// Position is used only to TELL THEM APART once both look like themes: a
/// qualifying span starting before the midpoint is the opening, one starting
/// after it is the ending.
///
/// When several qualify on the same side, **the LATEST wins**, and for the
/// opening that is measured rather than reasoned. It shipped the other way —
/// earliest-wins, on the theory that a repeated ~90s span later in the episode
/// is a scene rather than a second OP — and
/// `test_live/opening_span_choice_live_test.dart` shows that was backwards. Of
/// 105 chaptered files only SIX carry more than one candidate, and on the five
/// AniSkip can judge, the latest is right every time and by a wide margin: the
/// earliest scores 0–1% overlap with AniSkip's answer, the latest 92–100%. The
/// pattern is always the same — a cold open of coincidentally theme-like length
/// comes first, and the real opening starts exactly where it ends
/// (`Boushoku no Berserk` ep5: `0→88` then `88→178`, AniSkip `87.9→177.9`).
///
/// The earlier rationale conflated two different things. That an episode may
/// open cold with its OP at 498s while its neighbours start theirs at 0s proves
/// only that no rule may key on WHICH chapter it is — and that case carries a
/// single candidate, so it is decided identically either way.
///
/// The residual risk is the mirror image: an episode whose real OP comes first
/// and is followed by a coincidentally ~90s scene before the midpoint. That
/// shape does not occur anywhere in the reference library, while the cold-open
/// shape occurs five times; and corroboration is the backstop either way, since
/// a wrong pick disagrees with AniSkip and is then never auto-skipped. The
/// ending side keeps latest-wins, which it always had — multi-candidate endings
/// are UNMEASURED, so nothing there was changed on the strength of this.
///
/// Returns null rather than guessing when nothing is in the band. A file with
/// chapters that are merely scene divisions must yield NO skip data, not a
/// plausible-looking wrong one.
EpisodeSkips? inferSkipsFromChapters(
  List<ChapterMark> marks,
  Duration duration,
) {
  if (duration <= Duration.zero) return null;
  final spans = chapterSpans(marks, duration);
  if (spans.isEmpty) return null;

  final midpoint = duration ~/ 2;
  ChapterSpan? opening;
  ChapterSpan? ending;
  for (final span in spans) {
    final length = span.length;
    if (length < kOpeningMinLength || length > kOpeningMaxLength) continue;
    if (span.start < midpoint) {
      opening = span; // LATEST qualifying span before the midpoint — measured
    } else {
      ending = span; // latest qualifying span after it
    }
  }

  if (opening == null && ending == null) return null;
  return EpisodeSkips(
    intro: opening == null
        ? null
        : SkipRange(start: opening.start, end: opening.end),
    outro: ending == null
        ? null
        : SkipRange(start: ending.start, end: ending.end),
  );
}
