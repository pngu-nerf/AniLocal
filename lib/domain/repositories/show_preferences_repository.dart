import '../models/picture_mode.dart';
import '../models/show_preferences.dart';

/// Per-show preferences store — keyed to show identity (AniList id), sacred user
/// data that survives metadata refresh/rescan (no fill-path writer, seam #5).
/// Extensible: future per-show prefs add a method + a field on [ShowPreferences]
/// (and a column), not a parallel store.
abstract interface class ShowPreferencesRepository {
  /// Current preferences for a show; all-default when nothing is stored.
  Future<ShowPreferences> preferencesFor(int anilistId);

  /// All stored preferences, keyed by AniList id — for batch reads (the grid).
  /// Shows without an override are simply absent (treat as [ShowPreferences]()).
  Future<Map<int, ShowPreferences>> allPreferences();

  /// Set the cover display mode for a show (blur / removed / normal).
  Future<void> setPictureMode(int anilistId, PictureMode mode);

  /// Set whether the "Next episode" button is hidden for a show.
  Future<void> setNextEpisodeHidden(int anilistId, {required bool hidden});

  /// Overwrite EVERY cached show's next-episode-hidden pref to [hidden] — the
  /// global "Hide Next Episode" master switch applying to all shows (a
  /// deliberate overwrite of per-show choices, not a merge).
  Future<void> setAllNextEpisodeHidden({required bool hidden});
}
