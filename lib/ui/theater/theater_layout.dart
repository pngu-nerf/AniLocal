import 'package:flutter/material.dart';

import 'theater_layout_config.dart';

/// The ONLY place that knows where the theater zones sit and how big they are.
///
/// It reads a [TheaterLayoutConfig] and arranges a map of geometry-agnostic
/// zone widgets — the zones are handed a box and fill it; they have no opinion
/// about position or size. Moving a zone (rail side), resizing one (rail /
/// video fractions), or hiding one is a change to the config, handled here —
/// never a change to a zone widget. This is the repositioning seam.
///
/// Arrangement: a main column (video filling the space, series info directly
/// below it sized to its CONTENT — no flex-filler gap, no scroll) beside the
/// episode-list rail (width [TheaterLayoutConfig.railFraction], on
/// [TheaterLayoutConfig.railSide]).
class TheaterLayout extends StatelessWidget {
  const TheaterLayout({super.key, required this.config, required this.zones});

  final TheaterLayoutConfig config;

  /// The zone CONTENT, keyed by zone. The layout supplies the geometry; the
  /// widgets here know nothing about it. A missing entry for a visible zone is
  /// simply skipped.
  final Map<TheaterZone, Widget> zones;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // DEFENSIVE: a transient UNBOUNDED height/width can reach us during the
        // fullscreen-exit route pop. Sizing the video to `maxHeight *
        // videoFraction` would then be infinite and overflow (~100k "BOTTOM
        // OVERFLOWED"). Clamp to a bounded size (falling back to the view size)
        // and pin the whole arrangement to it, so NO descendant — the video
        // SizedBox, the info Expanded, the rail — can ever be handed an
        // unbounded dimension, whatever the transition timing. A no-op under
        // normal bounded layout (the clamp equals the incoming max).
        final view = MediaQuery.maybeOf(context)?.size;
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : (view?.width ?? 0);
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (view?.height ?? 0);
        if (maxWidth <= 0 || maxHeight <= 0) return const SizedBox.shrink();

        final showRail =
            config.shows(TheaterZone.episodeList) &&
            zones[TheaterZone.episodeList] != null;

        final Widget content;
        if (!showRail) {
          content = _mainColumn(maxHeight);
        } else {
          // Pixel widths from the fraction, so a future drag-to-resize just maps
          // a drag position back into [railFraction] — no structural change.
          final railWidth = maxWidth * config.railFraction;
          final rail = SizedBox(
            width: railWidth,
            child: zones[TheaterZone.episodeList],
          );
          final mainBox = SizedBox(
            width: maxWidth - railWidth,
            child: _mainColumn(maxHeight),
          );
          final ordered = config.railSide == TheaterSide.left
              ? [rail, mainBox]
              : [mainBox, rail];
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: ordered,
          );
        }

        return SizedBox(width: maxWidth, height: maxHeight, child: content);
      },
    );
  }

  /// Video fills the space above; series info sits directly below, sized to its
  /// CONTENT. The video is [Expanded] (it absorbs whatever height the info
  /// leaves — black bars are fine), and the info is a plain, inflexible child so
  /// it shrink-wraps its content: no flex filler, hence no dead whitespace below
  /// it (the actual fix), and no scroll.
  ///
  /// Why this can't overflow like the old fraction version: nothing here is
  /// sized by a constraint multiply that could go infinite. A Column measures
  /// its non-flex child (the info) with an UNBOUNDED main axis, so the info
  /// would take its full content height even if that exceeds the column — which
  /// would overflow on a very short window. So the info is wrapped in a
  /// `ConstrainedBox(maxHeight: height)`: in the normal case (content < height)
  /// it's a no-op and the info shrink-wraps to its content (the fix — no
  /// whitespace); on a too-short window it caps at the column height (the info
  /// zone clips its own content via its ClipRect) and the video gets whatever's
  /// left, down to zero — bounded, never overflowing. Either zone may be hidden.
  Widget _mainColumn(double height) {
    final showVideo =
        config.shows(TheaterZone.video) && zones[TheaterZone.video] != null;
    final showInfo =
        config.shows(TheaterZone.seriesInfo) &&
        zones[TheaterZone.seriesInfo] != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showVideo) Expanded(child: zones[TheaterZone.video]!),
        if (showInfo)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: zones[TheaterZone.seriesInfo]!,
          ),
      ],
    );
  }
}
