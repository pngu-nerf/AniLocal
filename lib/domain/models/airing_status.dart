/// Where a show is in its broadcast, in the app's own vocabulary. Every
/// metadata source has a word for it (AniList `RELEASING`, Kitsu `current`,
/// Jikan `Currently Airing`); the mappers translate into this ONE enum and
/// the cache stores its [token], so the UI never sees a provider's string.
enum AiringStatus {
  /// Episodes are still coming (AniList RELEASING and HIATUS — a pause is
  /// still "airing" as far as "do not forget this show" is concerned).
  releasing('releasing'),

  /// The last episode has aired (or the show was cancelled: no more coming).
  finished('finished'),

  /// Announced, nothing aired yet.
  notYetReleased('not_yet_released'),

  /// The source did not say, or has not been asked.
  unknown('unknown');

  const AiringStatus(this.token);

  /// The stored form (`series_cache.airing_status`).
  final String token;

  static AiringStatus fromToken(String? token) => AiringStatus.values
      .firstWhere((s) => s.token == token, orElse: () => AiringStatus.unknown);

  /// AniList `MediaStatus`.
  static AiringStatus fromAniList(String? status) => switch (status) {
    'RELEASING' || 'HIATUS' => releasing,
    'FINISHED' || 'CANCELLED' => finished,
    'NOT_YET_RELEASED' => notYetReleased,
    _ => unknown,
  };

  /// Kitsu `attributes.status`.
  static AiringStatus fromKitsu(String? status) => switch (status) {
    'current' => releasing,
    'finished' => finished,
    'upcoming' || 'unreleased' => notYetReleased,
    _ => unknown,
  };

  /// Jikan (MyAnimeList) `status`.
  static AiringStatus fromJikan(String? status) => switch (status) {
    'Currently Airing' => releasing,
    'Finished Airing' => finished,
    'Not yet aired' => notYetReleased,
    _ => unknown,
  };
}
