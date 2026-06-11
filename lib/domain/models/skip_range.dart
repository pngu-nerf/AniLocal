import 'package:equatable/equatable.dart';

/// A skippable time window within an episode (an intro/OP or outro/ED), as
/// absolute positions from the start of the file. Sourced from AniSkip at scan
/// time and cached; read offline during playback.
class SkipRange extends Equatable {
  const SkipRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  /// True if [position] falls inside this window.
  bool contains(Duration position) => position >= start && position < end;

  @override
  List<Object?> get props => [start, end];
}

/// The cached skip windows for one episode. Either may be null (AniSkip
/// coverage is partial — a missing window is normal, not an error).
class EpisodeSkips extends Equatable {
  const EpisodeSkips({this.intro, this.outro});

  /// OP / opening window.
  final SkipRange? intro;

  /// ED / ending window.
  final SkipRange? outro;

  bool get isEmpty => intro == null && outro == null;

  @override
  List<Object?> get props => [intro, outro];
}
