import 'dart:math' as math;

import '../domain/models/episode.dart';
import '../domain/models/skip_mode.dart';
import '../domain/models/skip_range.dart';

/// The player's DECISIONS, as pure functions of the numbers involved.
///
/// Everything here used to be inlined in the video zone's stream handlers,
/// where the only way to test "does the outro clamp stop short of the end" was
/// to play a file. Each rule is now a function of its inputs, the zone calls
/// it, and the rule can be pinned by a unit test that takes no player at all.
/// None of these touches the engine, the widget tree, or a repository.

/// How far short of the file end an in-episode seek lands.
///
/// mpv reports `completed` when playback reaches end-of-file, and a seek to
/// EXACTLY the duration reaches it at once. The app treats that completion as
/// "the viewer finished the episode" and advances, which would turn the outro
/// skip — documented to stay WITHIN the episode so a post-credits scene still
/// plays — into a bypass of the up-next countdown and its Cancel. Landing this
/// far before the end keeps completion an event only playback can produce.
const Duration kEndOfFileGuard = Duration(milliseconds: 750);

/// How close to the duration a `completed` must land to count as the episode
/// ENDING rather than the stream dying. A real ending is within a second or
/// so (the outro seek stops [kEndOfFileGuard] short; a VBR duration estimate
/// can be off by one); a drive pulled mid-play reports EOF wherever the
/// buffer ran dry, minutes from the end.
const Duration kCompletionTolerance = Duration(seconds: 5);

/// How long the position may sit still while the engine says it is PLAYING
/// before the session asks whether the file is still there. A volume that
/// vanishes mid-read makes mpv emit nothing — no completion, no error line,
/// pause still false — the frame simply freezes; this is the third signal of
/// a dead stream. Six seconds clears any ordinary buffering hiccup; a file
/// that is still present when probed is left to buffer.
const Duration kStallTolerance = Duration(seconds: 6);

/// The largest jump between two position reports that still looks like
/// PLAYBACK. Position events arrive several times a second; a seek jumps
/// farther, a stuck stream repeats the same value. An error is cleared only
/// after two consecutive steps of at most this — a seek on a dead stream
/// used to wipe the notice the stall watchdog had just raised.
const Duration kPlaybackStepMax = Duration(seconds: 2);

/// Where an outro skip should seek, or null when it should do nothing.
///
/// The target is the window's end, clamped to [duration] − [kEndOfFileGuard]
/// when the window overhangs the file (crowd-sourced timings are submitted
/// against another release, so an outro that runs past the end is ordinary).
/// A target at or behind [position] is a no-op rather than a backward jump: a
/// viewer who is already past the credits must never be pulled back into them.
/// An unknown duration (zero) trusts the window as-is — there is nothing to
/// clamp against yet.
Duration? outroSeekTarget({
  required SkipRange outro,
  required Duration duration,
  required Duration position,
}) {
  var target = outro.end;
  if (duration > Duration.zero) {
    final latest = duration - kEndOfFileGuard;
    if (target > latest) target = latest;
  }
  return target > position ? target : null;
}

/// The largest forward step between two consecutive position events that
/// still counts as CONTINUOUS playback at 1× — anything larger is a seek.
///
/// ASSUMPTION, stated here because the rules file requires it: media_kit
/// delivers position events several times per second during steady playback,
/// so consecutive events are well under this far apart in media time. At a
/// playback rate above 1× the same wall-clock gap covers proportionally more
/// media, so [shouldMarkFromPlayback] scales this by the rate — without that,
/// 2× playback could read as a continuous run of "seeks" and never mark the
/// episode watched.
const Duration kPositionEventGap = Duration(seconds: 2);

/// Whether the watched mark may be set by PLAYBACK reaching the threshold.
///
/// Only continuous playback may cross the watched threshold — a scrub near
/// the end must not complete the episode. The step from [previous] to
/// [position] is continuous when it is forward and no larger than
/// [kPositionEventGap] × [rate]; a backward step, or a larger jump, is a seek.
/// A zero [threshold] is the master off-switch; an unknown duration cannot be
/// judged.
bool shouldMarkFromPlayback({
  required Duration previous,
  required Duration position,
  required Duration duration,
  required Duration threshold,
  double rate = 1.0,
}) {
  if (threshold <= Duration.zero || duration <= Duration.zero) return false;
  final delta = position - previous;
  if (delta < Duration.zero) return false;
  if (delta > kPositionEventGap * rate) return false;
  return duration - position <= threshold;
}

/// An episode no longer than the threshold is inside the watched window from
/// its first frame, so it is watched the moment it opens (position-independent,
/// never a seek).
bool wholeEpisodeWithinThreshold({
  required Duration duration,
  required Duration threshold,
}) =>
    threshold > Duration.zero &&
    duration > Duration.zero &&
    duration <= threshold;

/// How long before the end the up-next pre-roll appears.
const Duration kPreRollLead = Duration(seconds: 5);

/// The countdown to show with [remaining] left, or null when the pre-roll is
/// not live: nothing left (the completion event advances, not the countdown),
/// or more than [lead] to go. Seconds are rounded UP so the label never reads
/// "0" while the episode is still playing, and capped at [lead] so the first
/// tick reads the lead, not the lead plus one.
int? preRollSecondsFor(Duration remaining, {Duration lead = kPreRollLead}) {
  if (remaining <= Duration.zero || remaining > lead) return null;
  return math.min(lead.inSeconds, (remaining.inMilliseconds + 999) ~/ 1000);
}

/// What the skip machinery does at one position: fire one automatic seek, or
/// offer buttons.
enum AutoSkip { none, intro, outro }

/// The outcome of [decideSkips]. [auto] is the seek to fire on its own (at most
/// one per call — the position event after a seek re-evaluates); the buttons
/// are what to OFFER when nothing fires.
class SkipDecision {
  const SkipDecision({
    this.auto = AutoSkip.none,
    this.showIntroButton = false,
    this.showOutroButton = false,
  });

  final AutoSkip auto;
  final bool showIntroButton;
  final bool showOutroButton;
}

/// The one rule for intro/outro at [position], from the episode's cached
/// windows and the per-episode state the caller keeps:
///
/// - [SkipMode.off] offers nothing and fires nothing, whatever is cached.
/// - Automatic skipping fires ONCE per window per episode ([introSkipped] /
///   [outroSkipped] are the caller's latch), so a manual seek back into a
///   skipped window is not yanked forward again.
/// - Automatic skipping is gated on confidence: a `conflicting` window (two
///   sources that disagree about where it is) is still offered as a button but
///   never fired — skipping into real content is what a viewer cannot undo, an
///   unoffered skip costs a keypress.
/// - When nothing fires, the buttons follow the windows; the outro button
///   yields to the up-next pre-roll while that occupies the bar.
SkipDecision decideSkips({
  required SkipMode mode,
  required Episode episode,
  required Duration position,
  required bool introSkipped,
  required bool outroSkipped,
  required bool preRollShowing,
}) {
  if (mode == SkipMode.off) return const SkipDecision();
  final intro = episode.introSkip;
  final outro = episode.outroSkip;
  final inIntro = intro != null && intro.contains(position);
  final inOutro = outro != null && outro.contains(position);
  if (mode == SkipMode.auto) {
    if (inIntro && !introSkipped && episode.introConfidence.allowsAutoSkip) {
      return const SkipDecision(auto: AutoSkip.intro);
    }
    if (inOutro && !outroSkipped && episode.outroConfidence.allowsAutoSkip) {
      return const SkipDecision(auto: AutoSkip.outro);
    }
  }
  return SkipDecision(
    showIntroButton: inIntro,
    showOutroButton: inOutro && !preRollShowing,
  );
}
