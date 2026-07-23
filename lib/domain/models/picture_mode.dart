/// How a show's cover is DISPLAYED. A per-show preference; the three states are
/// mutually exclusive (a show is in exactly one at a time). Purely a display
/// mode — the cached cover image is NEVER altered or deleted, so switching is
/// instant and works fully offline.
enum PictureMode {
  /// Show the normal cached AniList cover (or the default placeholder if the
  /// show never had one). The default state / "Reset to default".
  normal('normal'),

  /// Render the cached cover through a blur (NSFW / spoiler art).
  blur('blur'),

  /// Show a black placeholder with a question mark instead of the cover (the
  /// cached image is retained, just not displayed).
  removed('removed');

  const PictureMode(this.token);

  /// Stable string persisted in the per-show-preferences store.
  final String token;

  /// Map a stored token back to a mode; unknown/null → [normal] (the default).
  static PictureMode fromToken(String? token) => switch (token) {
    'blur' => PictureMode.blur,
    'removed' => PictureMode.removed,
    _ => PictureMode.normal,
  };
}
