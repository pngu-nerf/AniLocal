import '../../domain/models/skip_mode.dart';
import '../../domain/models/source_preference.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/show_preferences_repository.dart';
import 'cache_database.dart';

/// The one [SettingsRepository] impl, backed by the app_settings key/value store.
/// Owns every setting's key + default + parse in ONE place; injected as a single
/// object so screens read/write settings through it instead of threading
/// individual functions.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db, {required this.showPreferences});

  final CacheDatabase _db;

  /// Needed only by [setHideNextEpisode]'s master apply-to-all over per-show.
  final ShowPreferencesRepository showPreferences;

  static const _continueCollapsedKey = 'continue_watching_collapsed';
  static const _autoPlayNextKey = 'autoplay_next';
  static const _skipModeKey = 'skip_mode';
  static const _metadataSourceOrderKey = 'metadata_source_order';
  static const _skipSourceOrderKey = 'skip_source_order';
  // Watched-threshold (time-from-end), stored as whole milliseconds.
  static const _watchedThresholdKey = 'watched_threshold_ms';
  static const _missingEpisodesKey = 'missing_episodes_enabled';
  static const _hideNextEpisodeKey = 'hide_next_episode_global';
  static const _showContinueWatchingKey = 'show_continue_watching';
  static const _showSearchBarKey = 'show_search_bar';
  static const _railFractionKey = 'theater_rail_fraction';

  /// Points, not a fraction. A NEW key on purpose: the old
  /// `continue_panel_fraction` held values like 0.15, and 0.15 read as points is
  /// an invisible panel. Rather than guess a conversion — a fraction has no
  /// meaning in points without a reference window width, and inventing one would
  /// silently give people a width they never chose — the old key is simply no
  /// longer read, so an existing install falls back to the default width once
  /// and can drag from there. Nothing interprets the stale row; it is inert.
  static const _panelWidthKey = 'continue_panel_width';

  // Default rail width matches TheaterLayoutConfig.theaterDefault; default panel
  // width matches LibraryLayoutConfig. Each screen clamps to its own drag bounds.
  static const _railFractionDefault = 0.30;
  static const _panelWidthDefault = 300.0;

  @override
  Future<bool> loadContinueCollapsed() async =>
      await _db.getSetting(_continueCollapsedKey) == 'true';
  @override
  Future<void> setContinueCollapsed(bool collapsed) =>
      _db.setSetting(_continueCollapsedKey, '$collapsed');

  // Defaults ON: only an explicit 'false' disables.
  @override
  Future<bool> loadAutoPlayNext() async =>
      await _db.getSetting(_autoPlayNextKey) != 'false';
  @override
  Future<void> setAutoPlayNext(bool enabled) =>
      _db.setSetting(_autoPlayNextKey, '$enabled');

  // Defaults to "button" (SkipMode.fromToken maps null -> button).
  // Encoded as `token:1,token:0` — a token list like skip_mode, so no schema
  // change. Unknown/malformed entries are skipped rather than throwing: this is
  // user data in a hand-editable store, and a bad row must not brick settings.
  @override
  Future<List<SourcePreference>> loadMetadataSourceOrder() =>
      _loadOrder(_metadataSourceOrderKey);

  @override
  Future<void> setMetadataSourceOrder(List<SourcePreference> order) =>
      _saveOrder(_metadataSourceOrderKey, order);

  /// ONE encoder for both source lists, so the two families can never drift
  /// into different persisted formats.
  Future<List<SourcePreference>> _loadOrder(String key) async {
    final raw = await _db.getSetting(key);
    if (raw == null || raw.isEmpty) return const [];
    final out = <SourcePreference>[];
    for (final part in raw.split(',')) {
      final bits = part.split(':');
      final token = bits.first.trim();
      if (token.isEmpty) continue;
      out.add(
        SourcePreference(
          token: token,
          enabled: bits.length < 2 || bits[1] != '0',
        ),
      );
    }
    return out;
  }

  Future<void> _saveOrder(String key, List<SourcePreference> order) =>
      _db.setSetting(
        key,
        order.map((p) => '${p.token}:${p.enabled ? 1 : 0}').join(','),
      );

  @override
  Future<List<SourcePreference>> loadSkipSourceOrder() =>
      _loadOrder(_skipSourceOrderKey);

  @override
  Future<void> setSkipSourceOrder(List<SourcePreference> order) =>
      _saveOrder(_skipSourceOrderKey, order);

  @override
  Future<String?> loadSourceClientId(String token) async {
    final raw = await _db.getSetting(_sourceClientIdKey(token));
    return (raw == null || raw.trim().isEmpty) ? null : raw.trim();
  }

  @override
  Future<void> setSourceClientId(String token, String? clientId) =>
      _db.setSetting(_sourceClientIdKey(token), clientId?.trim() ?? '');

  static String _sourceClientIdKey(String token) => 'source_client_id_$token';

  @override
  Future<SkipMode> loadSkipMode() async =>
      SkipMode.fromToken(await _db.getSetting(_skipModeKey));
  @override
  Future<void> setSkipMode(SkipMode mode) =>
      _db.setSetting(_skipModeKey, mode.token);

  // Unset/unparseable -> the ~1:30 default; clamped to [0, 9:59] so a hand-edited
  // store can never yield an out-of-range value.
  @override
  Future<Duration> loadWatchedThreshold() async {
    final ms = int.tryParse(await _db.getSetting(_watchedThresholdKey) ?? '');
    if (ms == null) return watchedThresholdDefault;
    return Duration(
      milliseconds: ms.clamp(0, watchedThresholdMax.inMilliseconds),
    );
  }

  @override
  Future<void> setWatchedThreshold(Duration value) =>
      _db.setSetting(_watchedThresholdKey, '${value.inMilliseconds}');

  // Defaults ON: only an explicit 'false' disables.
  @override
  Future<bool> loadMissingEnabled() async =>
      await _db.getSetting(_missingEpisodesKey) != 'false';
  @override
  Future<void> setMissingEnabled(bool enabled) =>
      _db.setSetting(_missingEpisodesKey, '$enabled');

  @override
  Future<bool> loadHideNextEpisode() async =>
      await _db.getSetting(_hideNextEpisodeKey) == 'true';

  // Master apply-to-all: persist the flag AND overwrite every per-show value.
  @override
  Future<void> setHideNextEpisode(bool hidden) async {
    await _db.setSetting(_hideNextEpisodeKey, '$hidden');
    await showPreferences.setAllNextEpisodeHidden(hidden: hidden);
  }

  // Sidebar + search bar default VISIBLE: only an explicit 'false' hides them.
  @override
  Future<bool> loadShowContinueWatching() async =>
      await _db.getSetting(_showContinueWatchingKey) != 'false';
  @override
  Future<void> setShowContinueWatching(bool show) =>
      _db.setSetting(_showContinueWatchingKey, '$show');

  @override
  Future<bool> loadShowSearchBar() async =>
      await _db.getSetting(_showSearchBarKey) != 'false';
  @override
  Future<void> setShowSearchBar(bool show) =>
      _db.setSetting(_showSearchBarKey, '$show');

  // Fractions: unset/unparseable -> the default.
  @override
  Future<double> loadRailFraction() async =>
      double.tryParse(await _db.getSetting(_railFractionKey) ?? '') ??
      _railFractionDefault;
  @override
  Future<void> setRailFraction(double fraction) =>
      _db.setSetting(_railFractionKey, '$fraction');

  @override
  Future<double> loadPanelWidth() async =>
      double.tryParse(await _db.getSetting(_panelWidthKey) ?? '') ??
      _panelWidthDefault;
  @override
  Future<void> setPanelWidth(double width) =>
      _db.setSetting(_panelWidthKey, '$width');
}
