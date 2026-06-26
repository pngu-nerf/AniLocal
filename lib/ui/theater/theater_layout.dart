import 'package:flutter/material.dart';

import 'theater_layout_config.dart';

/// Pointer hit-width of the rail divider (wider than the painted line so it's
/// easy to grab). The visible line is thinner; this is just the grab target.
const double _dividerHitWidth = 10;

/// Locates the draggable rail divider (when [TheaterLayout.onRailResize] is set).
@visibleForTesting
const Key kRailDividerKey = Key('theater-rail-divider');

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
///
/// When [onRailResize] is supplied, a draggable divider sits at the rail
/// boundary: dragging it maps the pointer position back into a clamped
/// [TheaterLayoutConfig.railFraction] and reports it, so resizing the rail is
/// "change the config" — the same knob a Settings slider would turn. The
/// divider is *overlaid* (a [Positioned] strip) rather than inserted into the
/// [Row], so the existing pixel-width math is untouched and the video simply
/// reflows into whatever width the rail leaves.
class TheaterLayout extends StatelessWidget {
  const TheaterLayout({
    super.key,
    required this.config,
    required this.zones,
    this.onRailResize,
    this.onRailResizeEnd,
  });

  final TheaterLayoutConfig config;

  /// The zone CONTENT, keyed by zone. The layout supplies the geometry; the
  /// widgets here know nothing about it. A missing entry for a visible zone is
  /// simply skipped.
  final Map<TheaterZone, Widget> zones;

  /// Live-resize callback: fires continuously as the rail divider is dragged,
  /// with the new clamped [TheaterLayoutConfig.railFraction]. Null → no divider
  /// (the rail is a fixed fraction). The host re-renders with the new fraction.
  final ValueChanged<double>? onRailResize;

  /// Fires once when the drag ends — the cue to PERSIST the chosen fraction
  /// (the host already holds the live value from [onRailResize]).
  final VoidCallback? onRailResizeEnd;

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
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: ordered,
          );

          if (onRailResize == null) {
            content = row;
          } else {
            // The seam between main column and rail. Drag here resizes the rail
            // (and so, by reflow, the video). Overlaid — not a Row child — so
            // the width math above is untouched.
            final railOnLeft = config.railSide == TheaterSide.left;
            final boundaryX = railOnLeft ? railWidth : maxWidth - railWidth;
            content = Stack(
              children: [
                Positioned.fill(child: row),
                Positioned(
                  left: boundaryX - _dividerHitWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: _dividerHitWidth,
                  child: _RailDivider(
                    key: kRailDividerKey,
                    onDragDelta: (dx) {
                      // Dragging toward the rail's outer edge shrinks it;
                      // toward the video grows it. Sign depends on which side
                      // the rail is on.
                      final signed = railOnLeft ? dx : -dx;
                      final next = ((railWidth + signed) / maxWidth).clamp(
                        TheaterLayoutConfig.railFractionMin,
                        TheaterLayoutConfig.railFractionMax,
                      );
                      onRailResize!(next);
                    },
                    onDragEnd: onRailResizeEnd,
                  ),
                ),
              ],
            );
          }
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

/// The draggable seam between the main column and the episode rail. A thin
/// hover-aware line with a centered grab handle and a horizontal-resize cursor;
/// it reports drag deltas (the layout turns them into a clamped railFraction)
/// and signals when the drag ends (the cue to persist).
class _RailDivider extends StatefulWidget {
  const _RailDivider({super.key, required this.onDragDelta, this.onDragEnd});

  /// Incremental horizontal drag distance (logical px) since the last event.
  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDragEnd;

  @override
  State<_RailDivider> createState() => _RailDividerState();
}

class _RailDividerState extends State<_RailDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDragDelta(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: active ? 4 : 1.5,
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
            // A short centered grab handle, visible only when active, so the
            // seam reads as draggable without clutter at rest.
            child: active
                ? Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
