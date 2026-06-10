import 'package:equatable/equatable.dart';

import 'episode.dart';
import 'series.dart';

/// A resumable entry for the "Continue watching" row: the [series] (for art +
/// title) plus the in-progress [episode] (carrying its resume position and
/// duration for the progress indicator).
class ContinueWatching extends Equatable {
  const ContinueWatching({required this.series, required this.episode});

  final Series series;
  final Episode episode;

  @override
  List<Object?> get props => [series, episode];
}
