import 'package:equatable/equatable.dart';

import 'picture_mode.dart';

/// Per-show user preferences — sacred user data, keyed to show identity (AniList
/// id) and SURVIVING metadata refresh/rescan (same discipline as hide-state /
/// source-overrides: the fill path never writes it). Deliberately a small value
/// object with named fields so new per-show prefs are added cleanly (one field
/// here + one column), not bolted on ad-hoc.
class ShowPreferences extends Equatable {
  const ShowPreferences({
    this.pictureMode = PictureMode.normal,
    this.nextEpisodeHidden = false,
  });

  /// How the cover is displayed (default / blurred / removed).
  final PictureMode pictureMode;

  /// When true, the card's "Next episode" button is suppressed for this show.
  final bool nextEpisodeHidden;

  /// The absence of any override — used to prune an all-default row if desired.
  bool get isDefault => pictureMode == PictureMode.normal && !nextEpisodeHidden;

  ShowPreferences copyWith({
    PictureMode? pictureMode,
    bool? nextEpisodeHidden,
  }) => ShowPreferences(
    pictureMode: pictureMode ?? this.pictureMode,
    nextEpisodeHidden: nextEpisodeHidden ?? this.nextEpisodeHidden,
  );

  @override
  List<Object?> get props => [pictureMode, nextEpisodeHidden];
}
