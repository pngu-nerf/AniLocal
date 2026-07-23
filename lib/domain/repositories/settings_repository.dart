import '../models/skip_mode.dart';

/// Default watched-threshold on first run — ~a typical ED/credits length, so the
/// old proportional-90% behavior is roughly preserved. Lives here (domain) so
/// both the data impl and the UI can read it without a cross-layer import.
const watchedThresholdDefault = Duration(seconds: 90);

/// The largest watched-threshold the min:sec input accepts (9:59).
const watchedThresholdMax = Duration(minutes: 9, seconds: 59);

/// THE single source for app-wide preferences — one injected object that owns
/// every setting's load + persist, instead of threading ~20 individual
/// `load*/set*` functions through the widget tree (CLAUDE.md: "cross-cutting
/// config injected as one object, not threaded"). Adding a setting = one method
/// here + its impl + the reader; no re-plumbing.
///
/// Backed by the local key/value store; every getter has a sensible default so a
/// first run (or a hand-edited store) is always valid.
abstract interface class SettingsRepository {
  /// "Continue watching" section collapsed (homepage). Default false (expanded).
  Future<bool> loadContinueCollapsed();
  Future<void> setContinueCollapsed(bool collapsed);

  /// Auto-play the next episode at end. Default true.
  Future<bool> loadAutoPlayNext();
  Future<void> setAutoPlayNext(bool enabled);

  /// OP/ED skip mode. Default [SkipMode.button].
  Future<SkipMode> loadSkipMode();
  Future<void> setSkipMode(SkipMode mode);

  /// Watched-threshold as time-from-end (0:00 = auto-watched off). Default
  /// [watchedThresholdDefault]; always clamped to `[0, watchedThresholdMax]`.
  Future<Duration> loadWatchedThreshold();
  Future<void> setWatchedThreshold(Duration value);

  /// Missing-episodes feature (ghost tiles / Hidden tab / hidden-aware counts).
  /// Default true.
  Future<bool> loadMissingEnabled();
  Future<void> setMissingEnabled(bool enabled);

  /// Global "Hide next episode". Default false. [setHideNextEpisode] is a master
  /// apply-to-all: it persists the flag AND overwrites every per-show value.
  Future<bool> loadHideNextEpisode();
  Future<void> setHideNextEpisode(bool hidden);

  /// Homepage continue-watching sidebar visible. Default true.
  Future<bool> loadShowContinueWatching();
  Future<void> setShowContinueWatching(bool show);

  /// Homepage search bar visible. Default true.
  Future<bool> loadShowSearchBar();
  Future<void> setShowSearchBar(bool show);

  /// Theater rail width (fraction of total); the theater clamps to drag bounds.
  Future<double> loadRailFraction();
  Future<void> setRailFraction(double fraction);

  /// Continue-watching panel width (fraction); the library clamps to its bounds.
  Future<double> loadPanelFraction();
  Future<void> setPanelFraction(double fraction);
}
