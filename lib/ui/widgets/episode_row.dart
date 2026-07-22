import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// A leading episode-number badge — the ONE badge used by both the detail-page
/// episode list and the theater rail, so they can't drift. A filled cyan-deep
/// circle by default; [active] (rail now-playing) lights it full cyan; [ghost]
/// (a missing episode on the detail page) is a faded outline.
class EpisodeNumberBadge extends StatelessWidget {
  const EpisodeNumberBadge({
    super.key,
    required this.number,
    this.active = false,
    this.ghost = false,
  });

  final int number;

  /// Now-playing (rail): lit cyan fill, dark numerals.
  final bool active;

  /// Missing episode (detail): faded, outlined — no fill.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    if (ghost) {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Xp.textFaint, width: 1.5),
        ),
        child: Text(
          '$number',
          style: const TextStyle(color: Xp.textFaint, fontSize: 12),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Xp.accent : Xp.accentDeep,
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: active ? Xp.desktop : Xp.text,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The shared VISUAL scaffold for one episode row — a number badge, a
/// chrome-label title with an optional [detail] slot beneath it, and optional
/// [trailing] widgets. Used by BOTH the detail-page episode list and the
/// theater rail so their styling stays converged; each keeps its own tap
/// wrapper (the detail's press animation vs the rail's focus-free InkWell).
///
/// [nowPlayingCapable] rows (the rail) carry the now-playing affordance: a lit
/// row tint + a 3px cyan left bar when [active], animated, and the bar's slot is
/// always reserved so selecting a row never shifts its neighbours. Detail rows
/// leave it off, so present tiles line up with the (bar-less) ghost tiles.
class EpisodeRow extends StatelessWidget {
  const EpisodeRow({
    super.key,
    required this.number,
    required this.title,
    this.active = false,
    this.ghost = false,
    this.nowPlayingCapable = false,
    this.detail,
    this.trailing = const <Widget>[],
  });

  final int number;
  final String title;
  final bool active;
  final bool ghost;
  final bool nowPlayingCapable;

  /// A widget under the title (the rail's resume-progress bar; the detail's
  /// filename/resume subtitle). Null renders nothing.
  final Widget? detail;

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final labelColor = active
        ? Xp.accentBright
        : (ghost ? Xp.textFaint : Xp.text);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpisodeNumberBadge(number: number, active: active, ghost: ghost),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Episode label: the CHROME role (thin tracked matte), mixed-case
              // — the same role as the show titles, on both surfaces.
              ChromeLabel(
                title,
                upper: false,
                fontSize: 13,
                maxLines: 2,
                letterSpacing: 1,
                color: labelColor,
              ),
              if (detail != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: detail!),
            ],
          ),
        ),
        ...trailing,
      ],
    );

    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    if (!nowPlayingCapable) return Padding(padding: padding, child: content);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        // Now-playing row lit: dim-cyan fill + a lit cyan accent bar. The 3px
        // slot is always present (transparent when idle) so lighting a row never
        // nudges its neighbours.
        color: active ? Xp.accentDeep : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: active ? Xp.accent : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: padding,
      child: content,
    );
  }
}
