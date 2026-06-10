import 'package:equatable/equatable.dart';

import 'titles.dart';

/// A series related to another (sequel, prequel, side story, adaptation, …),
/// from AniList `relations`. Fetched in Stage 2; surfacing as watch-order is a
/// later stage. A minimal projection — enough to list and link the relation.
class RelatedSeries extends Equatable {
  const RelatedSeries({
    required this.anilistId,
    required this.relationType,
    required this.titles,
    this.format,
  });

  final int anilistId;

  /// AniList relation type, e.g. `SEQUEL`, `PREQUEL`, `SIDE_STORY`, `ADAPTATION`.
  final String relationType;
  final Titles titles;
  final String? format;

  @override
  List<Object?> get props => [anilistId, relationType, titles, format];
}
