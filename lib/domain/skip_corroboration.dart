import 'models/skip_range.dart';

/// How much a skip window is trusted.
///
/// The point of this is a gate, not a score: [conflicting] must not fire an
/// automatic skip, because skipping into real content is the one failure a
/// user cannot undo mid-episode, while an unoffered skip is a button press.
enum SkipConfidence {
  /// Two sources that derive their answer independently agree. Chapters come
  /// from the release group's authoring, AniSkip from human submissions — so
  /// agreement between them is genuine evidence, not one source echoing another.
  corroborated,

  /// Exactly one source had anything to say. Ordinary, and by far the common
  /// case: nothing is wrong, there is simply nothing to check against.
  single,

  /// Two sources both answered and disagree beyond the tolerance. Something is
  /// wrong and we cannot tell which one, so the window is offered but never
  /// fired automatically.
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

/// How far apart two sources may be and still be considered to agree.
///
/// ±2s, from measurement rather than taste: on the reference library AniSkip
/// and the release groups' own chapter marks agreed to within 0.5–0.7s. The
/// remaining margin covers chapter boundaries snapping to keyframes and
/// AniSkip's roughly one-second resolution.
const Duration kSkipCorroborationTolerance = Duration(seconds: 2);

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
    (a.start - b.start).abs() <= kSkipCorroborationTolerance &&
    (a.end - b.end).abs() <= kSkipCorroborationTolerance;

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
/// decides how much to trust them. So reordering sources still determines what
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
