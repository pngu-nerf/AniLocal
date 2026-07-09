import 'package:flutter/material.dart';

/// Pointer hit-width of a resize divider (wider than the painted line so it's
/// easy to grab). The visible line is thinner; this is just the grab target.
/// Layouts that overlay the divider offset it by half this width to centre the
/// grab strip on the boundary.
const double kResizeDividerHitWidth = 10;

/// The draggable seam between two panes — the single implementation shared by
/// the theater episode-rail and the library continue-watching panel. A thin
/// hover-aware line with a centered grab handle and a horizontal-resize cursor;
/// it reports incremental drag deltas (the layout turns them into a clamped
/// fraction) and signals when the drag ends (the cue to persist).
///
/// It is geometry-agnostic: it knows nothing about which pane it borders or how
/// wide anything is. The owning layout positions it on the boundary and maps the
/// deltas back into its own fraction — so "resize a pane" stays a config change.
class ResizeDivider extends StatefulWidget {
  const ResizeDivider({super.key, required this.onDragDelta, this.onDragEnd});

  /// Incremental horizontal drag distance (logical px) since the last event.
  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDragEnd;

  @override
  State<ResizeDivider> createState() => _ResizeDividerState();
}

class _ResizeDividerState extends State<ResizeDivider> {
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
