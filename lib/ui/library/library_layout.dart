import 'package:flutter/material.dart';

import 'library_layout_config.dart';

/// The ONLY place that knows where the landing-page zones sit and how big they
/// are. It reads a [LibraryLayoutConfig] and arranges a map of geometry-agnostic
/// zone widgets — the search field, the continue-watching panel, and the grid
/// are handed a box and fill it; they have no opinion about position or size.
///
/// Arrangement: the search field pinned full-width at the top (below the app's
/// top bar), and below it a row of the collapsible continue-watching panel
/// (width [LibraryLayoutConfig.panelWidth], or [collapsedPanelWidth] when
/// collapsed, on [LibraryLayoutConfig.panelSide]) beside the grid filling the
/// remaining space. This is the landing-page analogue of `TheaterLayout`.
class LibraryLayout extends StatelessWidget {
  const LibraryLayout({super.key, required this.config, required this.zones});

  final LibraryLayoutConfig config;

  /// The zone CONTENT, keyed by zone. A missing entry for a visible zone is
  /// simply skipped (e.g. the panel when there's nothing to continue), so the
  /// remaining zones reflow to fill the space.
  final Map<LibraryZone, Widget> zones;

  Widget? _zone(LibraryZone zone) => config.shows(zone) ? zones[zone] : null;

  @override
  Widget build(BuildContext context) {
    final search = _zone(LibraryZone.search);
    final panel = _zone(LibraryZone.continueWatching);
    final grid = _zone(LibraryZone.grid) ?? const SizedBox.shrink();

    final Widget below;
    if (panel == null) {
      below = grid;
    } else {
      final panelBox = SizedBox(
        width: config.panelCollapsed
            ? config.collapsedPanelWidth
            : config.panelWidth,
        child: panel,
      );
      final ordered = config.panelSide == LibrarySide.left
          ? [panelBox, const VerticalDivider(width: 1), Expanded(child: grid)]
          : [Expanded(child: grid), const VerticalDivider(width: 1), panelBox];
      below = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: ordered,
      );
    }

    return Column(
      children: [
        if (search != null) ...[search, const Divider(height: 1)],
        Expanded(child: below),
      ],
    );
  }
}
