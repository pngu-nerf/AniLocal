import 'models/skip_range.dart';

/// How much a skip window is trusted.
///
/// The point of this is a gate, not a score: [conflicting] must not fire an
/// automatic skip, because skipping into real content is the one failure a
/// user cannot undo mid-episode, while an unoffered skip is a button press.
enum SkipConfidence {
  /// Two sources that derive their answer independently place the theme in the
  /// same span. Chapters come from the release group's authoring, AniSkip from
  /// human submissions — so agreement between them is genuine evidence, not one
  /// source echoing another.
  ///
  /// "Same span", not "identical": the two disagree at the edges routinely and
  /// for legitimate reasons (a bundled service ident, a longer credits roll),
  /// and the leading source supplies the times regardless. See
  /// [kSkipCorroborationMinOverlap].
  corroborated,

  /// Exactly one source had anything to say. Ordinary, and by far the common
  /// case: nothing is wrong, there is simply nothing to check against.
  single,

  /// Two sources both answered and put the theme in materially DIFFERENT
  /// places. Something is wrong and we cannot tell which one, so the window is
  /// offered but never fired automatically.
  ///
  /// Not merely "the edges differ" — see [kSkipCorroborationMinOverlap]. Every
  /// such pair measured on the reference library turned out to be the leading
  /// source having picked the wrong chapter entirely, which is exactly the case
  /// worth refusing to auto-skip.
  conflicting;

  /// Stored form, so the DB never holds a magic number.
  int get stored => switch (this) {
    corroborated => 1,
    single => 0,
    conflicting => -1,
  };

  static SkipConfidence fromStored(int value) => switch (value) {
    1 => corroborated,
    -1 => conflicting,
    _ => single,
  };

  /// Whether a window this trusted may be skipped WITHOUT asking.
  bool get allowsAutoSkip => this != conflicting;
}

/// How much two windows must overlap to count as the same window.
///
/// Intersection over union, so it penalises BOTH a shifted window and a
/// mismatched length, and 0.60 is measured rather than picked. On the reference
/// library all 59 disagreeing pairs (28 intros, 31 outros) fell into two
/// populations with **nothing at all between 45% and 69%**:
///
/// * 50 pairs at 70–97%: the same theme, differing at the edges. Causes seen —
///   a uniform ~5s offset where AniSkip's submission targeted a different
///   release; a ~11s offset where the chapter bundles a streaming-service ident
///   in with the opening (skipping both is what a viewer wants); and an outro
///   whose start matched within a second but ran ~4s longer.
/// * 9 pairs at 0–44%: genuinely different places, and every one was the local
///   chapters being WRONG — `inferSkipsFromChapters` took a cold open of
///   coincidentally theme-like length, and the real opening began exactly where
///   that window ended.
///
/// The gap is so wide that the threshold is not a tuned number; anywhere in the
/// fifties or sixties separates the same two sets.
///
/// This REPLACED a ±2s test on each edge, which condemned the first population
/// along with the second — it treated a five-second edge difference exactly as
/// severely as a sixty-second difference in location, and a pair could conflict
/// on one loose edge while the other matched to within a second. What the gate
/// actually has to catch, now that the local source leads, is the top source
/// picking the wrong chapter, and that shows up as low overlap every time.
const double kSkipCorroborationMinOverlap = 0.60;

/// Intersection over union of two windows, 0 (disjoint) to 1 (identical).
double windowOverlap(SkipRange a, SkipRange b) {
  final start = a.start > b.start ? a.start : b.start;
  final end = a.end < b.end ? a.end : b.end;
  final intersection = end - start;
  if (intersection <= Duration.zero) return 0;
  final unionStart = a.start < b.start ? a.start : b.start;
  final unionEnd = a.end > b.end ? a.end : b.end;
  final union = unionEnd - unionStart;
  if (union <= Duration.zero) return 0;
  return intersection.inMicroseconds / union.inMicroseconds;
}

/// The inputs a skip row was resolved from, as one comparable string.
///
/// Stored on the row (`skip_segments.resolved_key`) so a refresh can tell
/// whether re-asking this episode could possibly produce a different answer.
/// That is the whole mechanism that stops the FIRST WRITER WINNING FOREVER:
/// without it, a refresh either re-asks every episode every time (unacceptable
/// — it is one network call per episode) or, as it did, never re-asks an
/// episode that already has a row, which silently made reordering sources and
/// switching on cross-checking inert on any library that had already been
/// scanned.
///
/// [sourcesInOrder] is the enabled, askable sources IN PRIORITY ORDER — order
/// is part of the key because it decides who supplies the times, and a source
/// that is switched off is simply absent. [corroborate] is part of it because
/// cross-checking changes the ANSWER, not just its cost: it asks every source
/// instead of stopping at the first, and only then can a window be judged
/// corroborated or conflicting.
///
/// [_ruleGeneration] is part of it because THE RULES ARE INPUTS TOO. The key has
/// to capture everything that could change the answer, and a row produced under
/// an older rule is exactly as stale as one produced from a different set of
/// sources. Bumping it re-resolves every row once, which is the only way a rule
/// change reaches a library that has already been scanned. Bump it whenever any
/// rule that could alter a stored window or verdict changes — the agreement
/// test in [reconcileWindow], or the inference in `inferSkipsFromChapters` —
/// but not for a refactor that cannot alter either.
///
/// Deliberately opaque and compared only for equality — nothing parses it back.
String skipResolutionKey(
  Iterable<String> sourcesInOrder, {
  required bool corroborate,
}) =>
    '${sourcesInOrder.join(',')}|${corroborate ? 'x' : '-'}'
    '|r$_ruleGeneration';

/// Generation of the rules that decide a stored row. 1 = the original ±2s test
/// on each edge; 2 = overlap (see [kSkipCorroborationMinOverlap]), which
/// reclassified 50 of 59 disagreeing pairs on the reference library as
/// agreement; 3 = the opening is the LATEST theme-length chapter before the
/// midpoint rather than the earliest, which fixed the nine windows that
/// generation 2 could only refuse to auto-skip.
const int _ruleGeneration = 3;

/// Drop a window shorter than [minimum].
///
/// A user-set floor on how short a skip may be. Sources occasionally mark a
/// few-second span — a logo sting, a scene divider a chapter parser read as a
/// theme — and offering those as "skip the intro" is noise at best and a
/// mis-skip at worst. A minimum of zero disables the filter entirely, which is
/// the default: nothing is discarded unless the user asks for it.
///
/// Applied on the READ path, not at write time, so changing the setting takes
/// effect immediately instead of needing a rescan of the whole library.
SkipRange? dropIfShorterThan(SkipRange? range, Duration minimum) {
  if (range == null || minimum <= Duration.zero) return range;
  return (range.end - range.start) < minimum ? null : range;
}

/// One source's answer for a single window.
class SkipCandidate {
  const SkipCandidate({required this.source, required this.range});

  /// The token of the source that produced it, for provenance.
  final String source;
  final SkipRange range;
}

/// The window chosen for one position, and how far to trust it.
class ResolvedWindow {
  const ResolvedWindow({
    required this.range,
    required this.source,
    required this.confidence,
  });

  final SkipRange range;
  final String source;
  final SkipConfidence confidence;
}

bool _agree(SkipRange a, SkipRange b) =>
    windowOverlap(a, b) >= kSkipCorroborationMinOverlap;

/// Reconcile what several sources said about ONE window (the intro, or the
/// outro), given [candidates] already in the user's source-priority order.
///
/// **A source that had nothing to say is not a disagreement.** Callers pass
/// only the sources that actually produced a window, so silence never counts
/// against agreement — partial coverage is the norm for skip data, and treating
/// an absent answer as dissent would mark almost everything conflicting and
/// disable auto-skip across the library.
///
/// The highest-priority candidate always supplies the times; corroboration only
/// decides how much to trust them — which is why agreement is judged on WHERE
/// the theme is rather than on the edges matching. So reordering sources still determines what
/// you get, exactly as it does with corroboration switched off.
ResolvedWindow? reconcileWindow(List<SkipCandidate> candidates) {
  if (candidates.isEmpty) return null;
  final chosen = candidates.first;
  if (candidates.length == 1) {
    return ResolvedWindow(
      range: chosen.range,
      source: chosen.source,
      confidence: SkipConfidence.single,
    );
  }
  // Agreement with ANY other source is enough. Requiring unanimity would let a
  // single bad third source veto two that agree.
  final corroborated = candidates
      .skip(1)
      .any((other) => _agree(chosen.range, other.range));
  return ResolvedWindow(
    range: chosen.range,
    source: chosen.source,
    confidence: corroborated
        ? SkipConfidence.corroborated
        : SkipConfidence.conflicting,
  );
}

/// What several sources said about one episode, reconciled.
class ReconciledSkips {
  const ReconciledSkips({this.intro, this.outro});

  final ResolvedWindow? intro;
  final ResolvedWindow? outro;

  bool get isEmpty => intro == null && outro == null;
}

/// Reconcile every source's answer for one episode.
///
/// [answers] is in the user's source-priority order. The two windows are judged
/// SEPARATELY: a corroborated intro alongside a lone outro is exactly what a
/// mixed library produces, and collapsing them to one verdict would either
/// forfeit the intro's corroboration or overstate the outro's.
ReconciledSkips reconcileSkips(
  List<({String source, EpisodeSkips skips})> answers,
) {
  final intros = <SkipCandidate>[];
  final outros = <SkipCandidate>[];
  for (final answer in answers) {
    final intro = answer.skips.intro;
    final outro = answer.skips.outro;
    // Only sources that actually HAVE this window take part in judging it.
    if (intro != null) {
      intros.add(SkipCandidate(source: answer.source, range: intro));
    }
    if (outro != null) {
      outros.add(SkipCandidate(source: answer.source, range: outro));
    }
  }
  return ReconciledSkips(
    intro: reconcileWindow(intros),
    outro: reconcileWindow(outros),
  );
}
