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
/// Arrangement: a main column (video on top, series info below, split by
/// [TheaterLayoutConfig.videoFraction]) beside the episode-list rail (width
/// [TheaterLayoutConfig.railFraction], on [TheaterLayoutConfig.railSide]).
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
        final showRail =
            config.shows(TheaterZone.episodeList) &&
            zones[TheaterZone.episodeList] != null;

        final main = _mainColumn(constraints.maxHeight);
        if (!showRail) return main;

        // Pixel widths from the fraction, so a future drag-to-resize just maps
        // a drag position back into [railFraction] — no structural change.
        final railWidth = constraints.maxWidth * config.railFraction;
        final rail = SizedBox(
          width: railWidth,
          child: zones[TheaterZone.episodeList],
        );
        final mainBox = SizedBox(
          width: constraints.maxWidth - railWidth,
          child: main,
        );

        final ordered = config.railSide == TheaterSide.left
            ? [rail, mainBox]
            : [mainBox, rail];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: ordered,
        );
      },
    );
  }

  /// Video over series info, split by [TheaterLayoutConfig.videoFraction].
  /// Either may be hidden via the config; whichever remains takes the space.
  Widget _mainColumn(double height) {
    final showVideo =
        config.shows(TheaterZone.video) && zones[TheaterZone.video] != null;
    final showInfo =
        config.shows(TheaterZone.seriesInfo) &&
        zones[TheaterZone.seriesInfo] != null;

    final children = <Widget>[
      if (showVideo)
        SizedBox(
          height: showInfo ? height * config.videoFraction : height,
          child: zones[TheaterZone.video],
        ),
      if (showInfo) Expanded(child: zones[TheaterZone.seriesInfo]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
