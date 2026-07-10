import 'package:equatable/equatable.dart';

import 'episode.dart';

/// The state of one episode POSITION in a series, from the missing-episodes
/// detection. This is the raw per-episode truth — deliberately NOT grouped —
/// so display concerns (ghost tiles, bundle grouping) and a future heatmap can
/// all consume the same data.
enum EpisodeStatus {
  /// A matched file exists for this position (in the library).
  present,

  /// No file for this position, and the user has NOT hidden it → a gap.
  missing,

  /// No file, but the user hid this position. Removed from the normal list and
  /// excluded from completeness counts. Kept in the raw truth so a heatmap /
  /// the Hidden tab can still enumerate it.
  hidden,
}

/// One episode position and its [status]. [episode] is set only when
/// [status] is [EpisodeStatus.present] (it's the in-library episode).
class EpisodeSlot extends Equatable {
  const EpisodeSlot({required this.number, required this.status, this.episode});

  /// The anchored (AniList-faithful) episode position this slot describes.
  final int number;
  final EpisodeStatus status;

  /// The present episode; null for missing/hidden slots.
  final Episode? episode;

  @override
  List<Object?> get props => [number, status, episode];
}
