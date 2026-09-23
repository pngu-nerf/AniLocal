import 'package:flutter/material.dart';

import '../../domain/airing.dart';
import '../theme/xp_tokens.dart';

/// The airing indicator on the episode-count line, rendered ONE way — the
/// card and the show page both compose it into their meta line the way they
/// compose the download tally. Dim while the show is airing and the library
/// is caught up ("Ep 9 · in 3d"); amber, the reserved status colour, when an
/// aired episode is not in the library ("Ep 8 out"). The words are computed
/// from the stored INSTANT against `now` at build time, never stored, so
/// they cannot go stale in the cache; the tooltip carries the full sentence.
abstract final class AiringLabel {
  static List<InlineSpan> spans(
    AiringState state, {
    required DateTime now,
    required double fontSize,
  }) {
    final (icon, colour, text, tooltip) = switch (state) {
      NewEpisode(:final episode, :final airedAt) => (
        Icons.new_releases_outlined,
        Xp.warning,
        'Ep $episode out',
        airedAt == null
            ? 'Episode $episode is out — not in your library yet'
            : 'Episode $episode aired ${relativeAirTime(airedAt, now)} '
                  '(${_calendar(airedAt)}) — not in your library yet',
      ),
      Airing(:final nextEpisode, :final nextAt) => (
        Icons.podcasts,
        Xp.textDim,
        switch ((nextEpisode, nextAt)) {
          (final n?, final at?) => 'Ep $n · ${relativeAirTime(at, now)}',
          (final n?, null) => 'Ep $n next',
          _ => 'Airing',
        },
        switch ((nextEpisode, nextAt)) {
          (final n?, final at?) => 'Airing — episode $n on ${_calendar(at)}',
          (final n?, null) => 'Airing — episode $n is next',
          _ => 'Airing — the next episode is not scheduled yet',
        },
      ),
    };
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Tooltip(
          message: tooltip,
          child: Text.rich(
            TextSpan(
              style: TextStyle(color: colour, fontSize: fontSize),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(icon, size: fontSize + 2, color: colour),
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

/// "in 3d", "in 5h", "now", "2h ago", "4d ago": the distance from [now] to
/// [at], coarse on purpose — an air time is a day-scale fact.
String relativeAirTime(DateTime at, DateTime now) {
  final d = at.difference(now);
  final abs = d.abs();
  if (abs < const Duration(hours: 1)) return 'now';
  final unit = abs < const Duration(hours: 48)
      ? '${abs.inHours}h'
      : '${abs.inDays}d';
  return d.isNegative ? '$unit ago' : 'in $unit';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Thu 1 Oct, 17:00" in local time — or the date alone at midnight, which
/// is what a finale DATE (day precision) is stored as.
String _calendar(DateTime at) {
  final t = at.toLocal();
  final day = '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  if (t.hour == 0 && t.minute == 0) return day;
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$day, $hh:$mm';
}
