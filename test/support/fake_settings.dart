import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/repositories/settings_repository.dart';

/// Shared test double for [SettingsRepository] — returns the production defaults
/// and no-ops on writes. ONE fake in ONE place, so adding a setting updates a
/// single test double (not the old ~20 threaded stub functions in every test).
class FakeSettings implements SettingsRepository {
  const FakeSettings();

  @override
  Future<bool> loadContinueCollapsed() async => false;
  @override
  Future<void> setContinueCollapsed(bool collapsed) async {}

  @override
  Future<bool> loadAutoPlayNext() async => true;
  @override
  Future<void> setAutoPlayNext(bool enabled) async {}

  @override
  Future<SkipMode> loadSkipMode() async => SkipMode.button;
  @override
  Future<void> setSkipMode(SkipMode mode) async {}

  @override
  Future<Duration> loadWatchedThreshold() async => const Duration(seconds: 90);
  @override
  Future<void> setWatchedThreshold(Duration value) async {}

  @override
  Future<bool> loadMissingEnabled() async => true;
  @override
  Future<void> setMissingEnabled(bool enabled) async {}

  @override
  Future<bool> loadHideNextEpisode() async => false;
  @override
  Future<void> setHideNextEpisode(bool hidden) async {}

  @override
  Future<bool> loadShowContinueWatching() async => true;
  @override
  Future<void> setShowContinueWatching(bool show) async {}

  @override
  Future<bool> loadShowSearchBar() async => true;
  @override
  Future<void> setShowSearchBar(bool show) async {}

  @override
  Future<double> loadRailFraction() async => 0.30;
  @override
  Future<void> setRailFraction(double fraction) async {}

  @override
  Future<double> loadPanelFraction() async => 0.22;
  @override
  Future<void> setPanelFraction(double fraction) async {}
}
