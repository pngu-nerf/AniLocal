import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import 'episode_row.dart';

/// The shared PRESENT-episode tile — a tappable [EpisodeRow], built the same way
/// by BOTH the detail-page episode list and the player rail, so the tile
/// assembly + tap wiring have one source of truth. Per-location differences are
/// config, not a second implementation:
///  - **rail:** [active]/[nowPlaying] highlight + a resume-progress bar passed as
///    [detail]; `onTap` swaps the video in place.
///  - **detail:** a filename/resume subtitle passed as [detail] + a trailing
///    source/menu; `onTap` opens the player.
///
/// SCOPE (deliberate): only the *tile* is shared. The surrounding LIST
/// scaffolding is NOT — the rail is a standalone scrolling panel of present-only
/// episodes with auto-scroll-to-current, while the detail list is a
/// page-embedded, heterogeneous (present / ghost / bundle) list with tabs +
/// search. Forcing those into one component would be a bad abstraction (see
/// `docs/tech-debt-audit.md` §A2), so each keeps its own container.
///
/// Tap uses a focus-free hover-highlight wrapper (a [GestureDetector], NOT
/// [InkWell]): it never requests keyboard focus — required so tapping the rail
/// can't steal the player's shortcut focus (player regression checklist) — and
/// needs no Material ancestor, so it works inside the detail's `XpPanel` well
/// too. (Hover tints an idle row [Xp.surfaceAlt]; a now-playing row keeps its
/// own lit fill, painted by [EpisodeRow] over the tint.)
class EpisodeTile extends StatefulWidget {
  const EpisodeTile({
    super.key,
    required this.number,
    required this.title,
    required this.onTap,
    this.active = false,
    this.nowPlaying = false,
    this.detail,
    this.trailing = const <Widget>[],
  });

  final int number;
  final String title;
  final VoidCallback onTap;

  /// Now-playing (rail): lights the row + badge.
  final bool active;

  /// Enable the now-playing affordance for this list (rail true; detail false).
  final bool nowPlaying;

  /// Slot under the title — rail: resume-progress bar; detail: subtitle.
  final Widget? detail;
  final List<Widget> trailing;

  @override
  State<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<EpisodeTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: _hover ? Xp.surfaceAlt : Colors.transparent,
          child: EpisodeRow(
            number: widget.number,
            title: widget.title,
            active: widget.active,
            nowPlayingCapable: widget.nowPlaying,
            detail: widget.detail,
            trailing: widget.trailing,
          ),
        ),
      ),
    );
  }
}
