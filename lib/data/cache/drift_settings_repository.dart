import '../../domain/models/skip_mode.dart';
import '../../domain/models/source_preference.dart';
import '../../domain/repositories/settings_repository.dart';
import 'cache_database.dart';

/// The one [SettingsRepository] impl, backed by the app_settings key/value store.
/// Owns every setting's key + default + parse in ONE place; injected as a single
/// object so screens read/write settings through it instead of threading
/// individual functions.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final CacheDatabase _db;

  static const _continueCollapsedKey = 'continue_watching_collapsed';
  static const _autoPlayNextKey = 'autoplay_next';
  static const _skipModeKey = 'skip_mode';
  static const _metadataSourceOrderKey = 'metadata_source_order';
  static const _skipSourceOrderKey = 'skip_source_order';
  static const _corroborateSkipsKey = 'corroborate_skips';
  static const _minSkipLengthKey = 'min_skip_length_seconds';
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

  /// Booleans are stored as `true`/`false`. One early key (`corroborate_skips`)
  /// was written as `1`/`0`, so reads accept both; writes are one form.
  Future<bool> _loadBool(String key, {required bool fallback}) async {
    switch (await _db.getSetting(key)) {
      case 'true' || '1':
        return true;
      case 'false' || '0':
        return false;
      default:
        return fallback;
    }
  }

  Future<void> _saveBool(String key, bool value) =>
      _db.setSetting(key, '$value');

  @override
  Future<bool> loadContinueCollapsed() =>
      _loadBool(_continueCollapsedKey, fallback: false);
  @override
  Future<void> setContinueCollapsed(bool collapsed) =>
      _saveBool(_continueCollapsedKey, collapsed);

  // Defaults ON.
  @override
  Future<bool> loadAutoPlayNext() =>
      _loadBool(_autoPlayNextKey, fallback: true);
  @override
  Future<void> setAutoPlayNext(bool enabled) =>
      _saveBool(_autoPlayNextKey, enabled);

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
    final seen = <String>{};
    for (final part in raw.split(',')) {
      final bits = part.split(':');
      final token = bits.first.trim();
      // A duplicate token (a hand edit, or a bug upstream) keeps its FIRST
      // position; the settings list must never show one source twice.
      if (token.isEmpty || !seen.add(token)) continue;
      out.add(
        SourcePreference(
          token: token,
          // Anything that is not an explicit '0' is enabled: the default.
          enabled: bits.length < 2 || bits[1].trim() != '0',
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
  Future<Duration> loadMinSkipLength() async {
    final raw = int.tryParse(await _db.getSetting(_minSkipLengthKey) ?? '');
    // Clamped: a hand-edited store must not be able to hide every skip, and a
    // negative floor is meaningless.
    return Duration(seconds: (raw ?? 0).clamp(0, minSkipLengthMax.inSeconds));
  }

  @override
  Future<void> setMinSkipLength(Duration value) => _db.setSetting(
    _minSkipLengthKey,
    '${value.inSeconds.clamp(0, minSkipLengthMax.inSeconds)}',
  );

  @override
  Future<bool> loadCorroborateSkips() =>
      _loadBool(_corroborateSkipsKey, fallback: false);

  @override
  Future<void> setCorroborateSkips(bool enabled) =>
      _saveBool(_corroborateSkipsKey, enabled);

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

  // Defaults ON.
  @override
  Future<bool> loadMissingEnabled() =>
      _loadBool(_missingEpisodesKey, fallback: true);
  @override
  Future<void> setMissingEnabled(bool enabled) =>
      _saveBool(_missingEpisodesKey, enabled);

  @override
  Future<bool> loadHideNextEpisode() =>
      _loadBool(_hideNextEpisodeKey, fallback: false);

  // Master apply-to-all: the flag AND every per-show value, in ONE transaction
  // — a crash between the two used to leave the switch saying "hidden" while
  // an arbitrary prefix of shows agreed. Done here, directly on the database,
  // which is what removed the construction cycle this repository used to have
  // with the library repository (it delegated this one call to it).
  @override
  Future<void> setHideNextEpisode(bool hidden) => _db.transaction(() async {
    await _saveBool(_hideNextEpisodeKey, hidden);
    await _db.setAllNextEpisodeHidden(hidden: hidden);
  });

  // Sidebar + search bar default VISIBLE.
  @override
  Future<bool> loadShowContinueWatching() =>
      _loadBool(_showContinueWatchingKey, fallback: true);
  @override
  Future<void> setShowContinueWatching(bool show) =>
      _saveBool(_showContinueWatchingKey, show);

  @override
  Future<bool> loadShowSearchBar() =>
      _loadBool(_showSearchBarKey, fallback: true);
  @override
  Future<void> setShowSearchBar(bool show) =>
      _saveBool(_showSearchBarKey, show);

  // Sizes: unset/unparseable -> the default; CLAMPED here like every other
  // setting, so a hand-edited store yields a usable value for any reader, not
  // only the screen that happens to clamp on its own.
  @override
  Future<double> loadRailFraction() async =>
      (double.tryParse(await _db.getSetting(_railFractionKey) ?? '') ??
              railFractionDefault)
          .clamp(railFractionMin, railFractionMax);
  @override
  Future<void> setRailFraction(double fraction) =>
      _db.setSetting(_railFractionKey, '$fraction');

  @override
  Future<double> loadPanelWidth() async =>
      (double.tryParse(await _db.getSetting(_panelWidthKey) ?? '') ??
              panelWidthDefault)
          .clamp(panelWidthMin, panelWidthMax);
  @override
  Future<void> setPanelWidth(double width) =>
      _db.setSetting(_panelWidthKey, '$width');
}
