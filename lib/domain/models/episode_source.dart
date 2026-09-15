import 'package:equatable/equatable.dart';

/// One copy of a logical episode — a file living under a particular library
/// folder. A multi-source episode has more than one of these (e.g. a NAS copy
/// and a local copy); they share the same episode identity and watch state.
///
/// [folderSortOrder] is the containing folder's priority rank (lower = higher
/// priority); the default source is the lowest-rank source. [folderPath] plus
/// [relativePath] is the source's durable identity for a manual override —
/// picking a source pins that file, which survives rescans and remounts (the
/// folder is a stable identity, the relative path lives inside it).
class EpisodeSource extends Equatable {
  const EpisodeSource({
    required this.fileRef,
    required this.folderPath,
    required this.folderSortOrder,
    this.relativePath = '',
  });

  /// The file's path within [folderPath] — what a pin names. Empty for a
  /// source built without one (tests, legacy callers).

  /// The file the player opens for this source.
  final String fileRef;

  /// The library folder this copy lives under — the source's identity.
  final String folderPath;
  final String relativePath;

  /// The containing folder's priority rank (lower = higher priority).
  final int folderSortOrder;

  @override
  List<Object?> get props => [
    fileRef,
    folderPath,
    folderSortOrder,
    relativePath,
  ];
}
