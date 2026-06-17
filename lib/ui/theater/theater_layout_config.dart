import 'package:flutter/foundation.dart';

/// The three zones of the theater watch screen. Identity only — a zone never
/// knows where it sits or how big it is; that lives entirely in
/// [TheaterLayoutConfig] + the layout layer (`theater_layout.dart`).
enum TheaterZone { video, seriesInfo, episodeList }

/// Which horizontal side the episode-list rail occupies. Flipping this MOVES
/// the list (e.g. right → left) without touching any zone widget.
enum TheaterSide { left, right }

/// The single source of truth for the theater's geometry: which side the
/// episode rail is on, how wide it is, how the main column splits between video
/// and info, and which zones are shown.
///
/// This is the seam the brief asks for. Every layout decision is a field here,
/// not a magic number scattered in the widget tree. The consequences are by
/// construction:
///  - **Move a zone** (rail left instead of right): set [railSide].
///  - **Resize a zone** (drag-to-resize / Settings later): set [railFraction]
///    or [videoFraction] — a future drag handle just writes these.
///  - **Hide / add a zone**: change [visibleZones].
///
/// None of those touch the zone widgets. For this pass the config is a fixed
/// [theaterDefault]; the point is the seam exists so later work is "change the
/// config", never "restructure the widgets".
@immutable
class TheaterLayoutConfig {
  const TheaterLayoutConfig({
    this.railSide = TheaterSide.right,
    this.railFraction = 0.30,
    this.videoFraction = 0.64,
    this.visibleZones = const {
      TheaterZone.video,
      TheaterZone.seriesInfo,
      TheaterZone.episodeList,
    },
  }) : assert(railFraction > 0 && railFraction < 1),
       assert(videoFraction > 0 && videoFraction <= 1);

  /// The side the episode-list rail sits on.
  final TheaterSide railSide;

  /// Episode-list rail width as a fraction of the total width (0–1).
  final double railFraction;

  /// Video height as a fraction of the main (video + info) column height
  /// (0–1). The series-info zone takes the remainder.
  final double videoFraction;

  /// The zones currently displayed. Hiding one is a config change.
  final Set<TheaterZone> visibleZones;

  bool shows(TheaterZone zone) => visibleZones.contains(zone);

  TheaterLayoutConfig copyWith({
    TheaterSide? railSide,
    double? railFraction,
    double? videoFraction,
    Set<TheaterZone>? visibleZones,
  }) => TheaterLayoutConfig(
    railSide: railSide ?? this.railSide,
    railFraction: railFraction ?? this.railFraction,
    videoFraction: videoFraction ?? this.videoFraction,
    visibleZones: visibleZones ?? this.visibleZones,
  );

  /// The default YouTube-style "theater" arrangement: video top-left with the
  /// series info below it, episode list as a rail on the right.
  static const TheaterLayoutConfig theaterDefault = TheaterLayoutConfig();
}
