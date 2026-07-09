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
///  - **Resize the panel**: set [panelFraction] — the expanded panel is a
///    fraction of the total width, dragged by the same [ResizeDivider] the
///    theater rail uses and clamped to [panelFractionMin]/[panelFractionMax].
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
    this.panelFraction = 0.22,
    this.collapsedPanelWidth = 44,
    this.visibleZones = const {
      LibraryZone.search,
      LibraryZone.continueWatching,
      LibraryZone.grid,
    },
  }) : assert(panelFraction > 0 && panelFraction < 1);

  /// The side the continue-watching panel sits on (left by default).
  final LibrarySide panelSide;

  /// Whether the continue-watching panel is collapsed to a thin strip. This is
  /// the persisted toggle relocated from the old "Continue watching" row.
  final bool panelCollapsed;

  /// Expanded panel width as a fraction of the total landing width (0–1) — the
  /// same knob shape as [TheaterLayoutConfig.railFraction], turned by the same
  /// draggable [ResizeDivider].
  final double panelFraction;

  /// Drag bounds for the panel. The divider clamps [panelFraction] to this range
  /// so the panel can neither shrink to nothing nor crowd out the grid; a
  /// persisted value is clamped to this on load too.
  static const double panelFractionMin = 0.15;
  static const double panelFractionMax = 0.4;

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
    double? panelFraction,
    double? collapsedPanelWidth,
    Set<LibraryZone>? visibleZones,
  }) => LibraryLayoutConfig(
    panelSide: panelSide ?? this.panelSide,
    panelCollapsed: panelCollapsed ?? this.panelCollapsed,
    panelFraction: panelFraction ?? this.panelFraction,
    collapsedPanelWidth: collapsedPanelWidth ?? this.collapsedPanelWidth,
    visibleZones: visibleZones ?? this.visibleZones,
  );

  /// The default arrangement: search pinned at the top, continue-watching panel
  /// on the left, grid filling the rest.
  static const LibraryLayoutConfig landingDefault = LibraryLayoutConfig();
}
