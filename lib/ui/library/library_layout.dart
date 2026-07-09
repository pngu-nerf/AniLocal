import 'package:flutter/material.dart';

import '../resize_divider.dart';
import 'library_layout_config.dart';

/// Locates the draggable continue-watching divider (when
/// [LibraryLayout.onPanelResize] is set and the panel is expanded).
@visibleForTesting
const Key kContinuePanelDividerKey = Key('continue-panel-divider');

/// The ONLY place that knows where the landing-page zones sit and how big they
/// are. It reads a [LibraryLayoutConfig] and arranges a map of geometry-agnostic
/// zone widgets — the search field, the continue-watching panel, and the grid
/// are handed a box and fill it; they have no opinion about position or size.
///
/// Arrangement: the search field pinned full-width at the top (below the app's
/// top bar), and below it a row of the collapsible continue-watching panel
/// (a [LibraryLayoutConfig.panelFraction] of the width, or [collapsedPanelWidth]
/// when collapsed, on [LibraryLayoutConfig.panelSide]) beside the grid filling
/// the remaining space. When expanded, a draggable [ResizeDivider] — the very
/// one the theater rail uses — sits on the boundary. Landing-page analogue of
/// `TheaterLayout`.
class LibraryLayout extends StatelessWidget {
  const LibraryLayout({
    super.key,
    required this.config,
    required this.zones,
    this.onPanelResize,
    this.onPanelResizeEnd,
  });

  final LibraryLayoutConfig config;

  /// The zone CONTENT, keyed by zone. A missing entry for a visible zone is
  /// simply skipped (e.g. the panel when there's nothing to continue), so the
  /// remaining zones reflow to fill the space.
  final Map<LibraryZone, Widget> zones;

  /// Live-resize callback: fires continuously as the panel divider is dragged,
  /// with the new clamped [LibraryLayoutConfig.panelFraction]. Null (or a
  /// collapsed panel) → no divider (the panel is a fixed width). Mirrors the
  /// theater's `onRailResize` and drives the same [ResizeDivider].
  final ValueChanged<double>? onPanelResize;

  /// Fires once when the drag ends — the cue to PERSIST the chosen fraction.
  final VoidCallback? onPanelResizeEnd;

  Widget? _zone(LibraryZone zone) => config.shows(zone) ? zones[zone] : null;

  @override
  Widget build(BuildContext context) {
    final search = _zone(LibraryZone.search);
    final panel = _zone(LibraryZone.continueWatching);
    final grid = _zone(LibraryZone.grid) ?? const SizedBox.shrink();

    final Widget below;
    if (panel == null) {
      below = grid;
    } else if (config.panelCollapsed) {
      // Collapsed: a fixed thin strip, no divider (like the theater rail when
      // hidden). Each pane sits in its own beveled well, so no rule between them.
      final panelBox = SizedBox(
        width: config.collapsedPanelWidth,
        child: panel,
      );
      below = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: config.panelSide == LibrarySide.left
            ? [panelBox, Expanded(child: grid)]
            : [Expanded(child: grid), panelBox],
      );
    } else {
      // Expanded: width is a fraction of the total, with the SAME overlaid
      // draggable divider the theater uses — dragging maps the pointer back into
      // a clamped panelFraction (so "resize the panel" stays a config change).
      below = LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final panelWidth = maxWidth * config.panelFraction;
          final panelBox = SizedBox(width: panelWidth, child: panel);
          final panelOnLeft = config.panelSide == LibrarySide.left;
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: panelOnLeft
                ? [panelBox, Expanded(child: grid)]
                : [Expanded(child: grid), panelBox],
          );
          if (onPanelResize == null) return row;
          // Boundary sits at the panel's inner edge. Overlaid (not a Row child)
          // so the width math above is untouched and the grid simply reflows.
          final boundaryX = panelOnLeft ? panelWidth : maxWidth - panelWidth;
          return Stack(
            children: [
              Positioned.fill(child: row),
              Positioned(
                left: boundaryX - kResizeDividerHitWidth / 2,
                top: 0,
                bottom: 0,
                width: kResizeDividerHitWidth,
                child: ResizeDivider(
                  key: kContinuePanelDividerKey,
                  onDragDelta: (dx) {
                    // Dragging toward the panel's outer edge shrinks it; toward
                    // the grid grows it. Sign depends on which side it's on.
                    final signed = panelOnLeft ? dx : -dx;
                    final next = ((panelWidth + signed) / maxWidth).clamp(
                      LibraryLayoutConfig.panelFractionMin,
                      LibraryLayoutConfig.panelFractionMax,
                    );
                    onPanelResize!(next);
                  },
                  onDragEnd: onPanelResizeEnd,
                ),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        ?search,
        Expanded(child: below),
      ],
    );
  }
}
