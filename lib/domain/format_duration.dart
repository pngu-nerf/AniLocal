/// The ONE clock format for a duration in user copy: `m:ss`, widening to
/// `h:mm:ss` once it reaches an hour, so ninety minutes reads `1:30:00` and
/// never `90:00`. Whole seconds, floored — a player clock counts up through
/// the second it is in.
///
/// Three copies of this had already drifted (the show page had no hours
/// branch); CLAUDE.md names a shared `formatDuration` as the required single
/// source, and this is it.
String formatDuration(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
