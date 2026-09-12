import 'package:flutter/material.dart';

import '../../domain/missing_episodes.dart';
import '../theme/xp_tokens.dart';

/// The "⬇ N of M +X" downloaded-episode indicator, rendered ONE way.
///
/// The library card and the show page each drew this themselves and had
/// drifted (icon 13 vs 15, font 11 vs 12, a different gap before the "+X").
/// [spans] is for a caller composing it into a longer line — the card puts
/// the show type before it — and the widget is the standalone form.
class DownloadTallyLabel extends StatelessWidget {
  const DownloadTallyLabel(this.tally, {super.key, this.compact = false});

  final DownloadTally tally;

  /// The card's smaller variant.
  final bool compact;

  /// The indicator as inline spans, styled for [fontSize]. A flat,
  /// single-colour Material icon rather than the ⬇ emoji, which the OS draws
  /// full-colour in a box; the WidgetSpan child does not inherit the text
  /// colour, so it is given the line's neutral colour explicitly.
  static List<InlineSpan> spans(
    DownloadTally tally, {
    required double fontSize,
  }) {
    final m = tally.total;
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(Icons.download, size: fontSize + 2, color: Xp.textDim),
        ),
      ),
      // "N of M" — the total M is dropped when unknown (rare) → just "N".
      TextSpan(text: m != null ? '${tally.inRange} of $m' : '${tally.inRange}'),
      // Only the "+X" (extra out-of-range downloads) is coloured: amber is
      // the reserved attention colour, and the tally itself is neutral.
      if (tally.outOfRange > 0)
        TextSpan(
          text: ' +${tally.outOfRange}',
          style: const TextStyle(color: Xp.warning),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final size = compact ? Xp.fontSizeCaption : Xp.fontSizeBody;
    return Text.rich(
      TextSpan(
        style: TextStyle(color: Xp.textDim, fontSize: size),
        children: spans(tally, fontSize: size),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
