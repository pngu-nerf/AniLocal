import 'package:equatable/equatable.dart';

/// One playable episode file mapped to a [Series].
///
/// [fileRef] is the local file path and is the stable identity for watch state.
/// [watched] and [resumePosition] are local-only (no tracker sync — see
/// roadmap Stage 6). `copyWith` will be added when watch-state mutation lands.
class Episode extends Equatable {
  const Episode({
    required this.number,
    required this.fileRef,
    this.title,
    this.watched = false,
    this.resumePosition = Duration.zero,
  });

  final int number;
  final String fileRef;
  final String? title;
  final bool watched;
  final Duration resumePosition;

  @override
  List<Object?> get props => [number, fileRef, title, watched, resumePosition];
}
