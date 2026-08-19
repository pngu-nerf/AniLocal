import '../../domain/repositories/settings_repository.dart';

/// Parse a `m:ss` watched-threshold entry, or null if invalid. Rejects
/// non-numeric input, seconds ≥ 60, values past [watchedThresholdMax] (9:59),
/// and anything not shaped `minutes:seconds`. Pure, so it's unit-testable — the
/// single gate that keeps a blank/garbage value from ever being persisted.
Duration? parseWatchedThreshold(String input) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})\s*$').firstMatch(input);
  if (m == null) return null;
  final minutes = int.parse(m.group(1)!);
  final seconds = int.parse(m.group(2)!);
  if (seconds >= 60) return null;
  final total = Duration(minutes: minutes, seconds: seconds);
  if (total > watchedThresholdMax) return null;
  return total; // Duration can't be negative from non-negative parts.
}

/// Format a watched-threshold as `m:ss` (e.g. 90s → "1:30", zero → "0:00").
String formatWatchedThreshold(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
