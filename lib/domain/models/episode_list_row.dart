import 'package:equatable/equatable.dart';

import 'episode.dart';

/// A row in the show's episode list, AFTER display-grouping the per-episode
/// truth. Recomputed live from the slots — never stored — so hiding an episode
/// mid-run re-groups automatically. One of three shapes:
///  - [PresentRow]       an in-library episode,
///  - [MissingSingleRow] one isolated missing episode (a ghost),
///  - [MissingBundleRow] a consecutive run of 2+ missing episodes, collapsed.
sealed class EpisodeListRow extends Equatable {
  const EpisodeListRow();
}

/// A present (in-library) episode.
class PresentRow extends EpisodeListRow {
  const PresentRow(this.episode);
  final Episode episode;
  @override
  List<Object?> get props => [episode];
}

/// A single missing episode (not part of a run of 2+).
class MissingSingleRow extends EpisodeListRow {
  const MissingSingleRow(this.number);
  final int number;
  @override
  List<Object?> get props => [number];
}

/// A consecutive run of 2+ missing episodes, shown as ONE bundle tile: [first]
/// on top, [last] on the bottom, "these two and everything between". [numbers]
/// is the full per-episode list the bundle stands for (so "hide all" hides each
/// one individually).
class MissingBundleRow extends EpisodeListRow {
  const MissingBundleRow({required this.numbers}) : assert(numbers.length >= 2);
  final List<int> numbers;
  int get first => numbers.first;
  int get last => numbers.last;
  @override
  List<Object?> get props => [numbers];
}
