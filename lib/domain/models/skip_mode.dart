/// How the player treats cached intro/outro skip windows. Governs playback-time
/// behavior only — skip timestamps are fetched/cached regardless of mode, so
/// switching to a skip mode later works offline on already-synced episodes.
enum SkipMode {
  /// Never show or perform skips, even with data cached.
  off,

  /// Show a "Skip Intro"/"Skip Outro" button during a cached window (default).
  button,

  /// Automatically jump past the segment when playback enters a cached window.
  auto;

  /// Persisted token (stored in app_settings). Unknown/missing → [button].
  String get token => name;
  static SkipMode fromToken(String? token) =>
      SkipMode.values.firstWhere((m) => m.name == token, orElse: () => button);
}
