import 'package:equatable/equatable.dart';

import 'titles.dart';

/// A single anime entry, keyed by its AniList ID.
///
/// Minimal projection of what the UI renders — not a clone of the AniList
/// schema. Mapping from AniList DTOs lives in `lib/data/anilist`; persistence
/// lives in `lib/data/cache`. This type carries no JSON or DB annotations.
class Series extends Equatable {
  const Series({
    required this.anilistId,
    required this.titles,
    this.format,
    this.coverImageRef,
  });

  final int anilistId;
  final Titles titles;

  /// AniList format, e.g. `TV`, `MOVIE`, `OVA`. Free-form for now.
  final String? format;

  /// Reference to cover art — a local cached file path or remote URL,
  /// resolved by the repository layer. The UI does not care which.
  final String? coverImageRef;

  @override
  List<Object?> get props => [anilistId, titles, format, coverImageRef];
}
