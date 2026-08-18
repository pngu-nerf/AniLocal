import 'package:flutter/foundation.dart';

/// The zones of the landing/library page. Identity only — a zone never knows
/// where it sits or how wide it is; that lives entirely in [LibraryLayoutConfig]
/// + the layout layer (`library_layout.dart`). Mirrors the theater seam
/// (`TheaterZone` / `TheaterLayoutConfig`).
enum LibraryZone {
  /// The live library search field, pinned full-width below the top bar.
  search,

  /// The collapsible "Continue watching" side panel.
  continueWatching,

  /// The library grid, filling the space the panel leaves.
  grid,
}

/// Which horizontal side the "Continue watching" panel occupies. Flipping this
/// MOVES the panel (e.g. left → right) without touching any zone widget.
enum LibrarySide { left, right }

/// The single source of truth for the landing page's geometry: which side the
/// continue-watching panel is on, how wide it is expanded vs collapsed, and
/// which zones are shown.
///
/// This is the same repositioning seam the theater screen uses. Every layout
/// decision is a field here, not a magic number scattered in the widget tree:
///  - **Move the panel** (left ↔ right): set [panelSide].
///  - **Collapse / expand the panel**: set [panelCollapsed] (the layout swaps to
///    [collapsedPanelWidth]); the panel widget reads the same flag to render a
///    header-only strip. Persisted across launches (reuses the old row's toggle).
///  - **Resize the panel**: set [panelWidth] — an absolute width in logical
///    points, dragged by the same [ResizeDivider] the theater rail uses and
///    clamped to [panelWidthMin]/[panelWidthMax].
///  - **Hide / add a zone** (e.g. no continue-watching entries): change
///    [visibleZones] / omit the zone from the layout's zone map.
///
/// None of those touch the zone widgets — the search field, the panel, the grid
/// are all geometry-agnostic and simply fill the box the layout hands them.
@immutable
class LibraryLayoutConfig {
  const LibraryLayoutConfig({
    this.panelSide = LibrarySide.left,
    this.panelCollapsed = false,
    this.panelWidth = 300,
    this.collapsedPanelWidth = 44,
    this.visibleZones = const {
      LibraryZone.search,
      LibraryZone.continueWatching,
      LibraryZone.grid,
    },
  }) : assert(panelWidth > 0);

  /// The side the continue-watching panel sits on (left by default).
  final LibrarySide panelSide;

  /// Whether the continue-watching panel is collapsed to a thin strip. This is
  /// the persisted toggle relocated from the old "Continue watching" row.
  final bool panelCollapsed;

  /// Expanded panel width in LOGICAL POINTS — an absolute size, not a fraction
  /// of the window.
  ///
  /// It used to be a fraction, which had two faults that were really one: the
  /// panel rescaled on every window resize (a sidebar has a natural reading
  /// width; it shouldn't grow because you widened the window), and the
  /// fraction-clamp guaranteed nothing real — "15% at minimum" is a usable
  /// column on a wide display and an unreadable sliver on a narrow one. Sizing
  /// in points fixes both: the panel keeps the width you gave it and the GRID
  /// absorbs window resizes, and the clamp below is a genuine minimum.
  final double panelWidth;

  /// Drag bounds, in points. The divider clamps to this range and a persisted
  /// value is clamped on load too.
  ///
  /// The minimum is deliberately modest. The app enforces a 600pt minimum WINDOW
  /// width (`contentMinSize` in the runner), so a 220pt sidebar still leaves
  /// ~380pt of grid at the tightest window the user can make — no proportional
  /// cap or collapse-below-threshold rule needed, because the window minimum is
  /// already the safety net.
  static const double panelWidthMin = 220;
  static const double panelWidthMax = 480;

  /// Panel width (logical px) when collapsed (just the expand affordance).
  final double collapsedPanelWidth;

  /// The zones currently displayed. Hiding one is a config change. (The layout
  /// also skips any visible zone with no widget supplied — e.g. the panel when
  /// there's nothing to continue.)
  final Set<LibraryZone> visibleZones;

  bool shows(LibraryZone zone) => visibleZones.contains(zone);

  LibraryLayoutConfig copyWith({
    LibrarySide? panelSide,
    bool? panelCollapsed,
    double? panelWidth,
    double? collapsedPanelWidth,
    Set<LibraryZone>? visibleZones,
  }) => LibraryLayoutConfig(
    panelSide: panelSide ?? this.panelSide,
    panelCollapsed: panelCollapsed ?? this.panelCollapsed,
    panelWidth: panelWidth ?? this.panelWidth,
    collapsedPanelWidth: collapsedPanelWidth ?? this.collapsedPanelWidth,
    visibleZones: visibleZones ?? this.visibleZones,
  );

  /// The default arrangement: search pinned at the top, continue-watching panel
  /// on the left, grid filling the rest.
  static const LibraryLayoutConfig landingDefault = LibraryLayoutConfig();
}
