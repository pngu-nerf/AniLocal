import 'dart:async';
import 'package:flutter/widgets.dart';

import '../../domain/models/skip_mode.dart';
import '../../domain/repositories/settings_repository.dart';
import 'watched_threshold.dart';

/// The open window's live view of the settings, and the ONLY thing the panels
/// talk to.
///
/// It exists because the settings now live on several panels: the values have
/// to outlive any one panel (switching category and back must not reload or
/// reset anything), and the m:ss field's controller has to survive with them.
/// A model here is not a second persistence layer — every setter writes
/// straight through to the injected [SettingsRepository], which remains the
/// single source of truth. This is a read-cache for the seconds the window is
/// open, mirroring what the old dialog held in its `StatefulBuilder` locals.
///
/// Writes are fire-and-forget, exactly as before: the control flips
/// immediately, and the repository persists behind it.
class SettingsModel extends ChangeNotifier {
  SettingsModel({
    required this.repository,
    required this.unmatchedCount,
    required this.autoPlayNext,
    required this.skipMode,
    required this.watchedThreshold,
    required this.missingEnabled,
    required this.corroborateSkips,
    required this.minSkipLength,
    required this.hideNextEpisode,
    required this.showContinueWatching,
    required this.showSearchBar,
  }) : thresholdController = TextEditingController(
         text: formatWatchedThreshold(watchedThreshold),
       );

  /// Load every setting once, before the window opens — same values, same
  /// order, same defaults as the old dialog's preamble.
  static Future<SettingsModel> load({
    required SettingsRepository repository,
    required Future<int> Function() loadUnmatchedCount,
  }) async {
    // Independent reads, issued together: ten sequential awaits before the
    // window could open was the whole wait behind the ⚙ click.
    final (
      (
        autoPlayNext,
        skipMode,
        watchedThreshold,
        missingEnabled,
        corroborateSkips,
      ),
      (
        minSkipLength,
        hideNextEpisode,
        showContinueWatching,
        showSearchBar,
        unmatchedCount,
      ),
    ) = await (
      (
        repository.loadAutoPlayNext(),
        repository.loadSkipMode(),
        repository.loadWatchedThreshold(),
        repository.loadMissingEnabled(),
        repository.loadCorroborateSkips(),
      ).wait,
      (
        repository.loadMinSkipLength(),
        repository.loadHideNextEpisode(),
        repository.loadShowContinueWatching(),
        repository.loadShowSearchBar(),
        loadUnmatchedCount(),
      ).wait,
    ).wait;
    return SettingsModel(
      repository: repository,
      autoPlayNext: autoPlayNext,
      skipMode: skipMode,
      watchedThreshold: watchedThreshold,
      missingEnabled: missingEnabled,
      corroborateSkips: corroborateSkips,
      minSkipLength: minSkipLength,
      hideNextEpisode: hideNextEpisode,
      showContinueWatching: showContinueWatching,
      showSearchBar: showSearchBar,
      unmatchedCount: unmatchedCount,
    );
  }

  final SettingsRepository repository;

  /// Snapshot, deliberately: it labels a row that navigates away, and the
  /// window is closed before anything can change the count.
  final int unmatchedCount;

  /// Seeded from the persisted value and owned here so the field keeps its text
  /// across category switches.
  final TextEditingController thresholdController;

  /// Mutated ONLY through the `set*` methods below, which persist and notify.
  /// Reading them directly is what the panels do; writing them directly would
  /// skip the repository, so don't.
  bool autoPlayNext;
  SkipMode skipMode;
  Duration watchedThreshold;
  bool missingEnabled;

  /// Cross-check skip sources against each other (Settings > Skip).
  bool corroborateSkips;

  /// Ignore skip windows shorter than this. Zero = no filter.
  Duration minSkipLength;

  /// NOTE the stored sense: true means the next-episode button is HIDDEN. The
  /// Homepage panel presents it as the positive "Next episode", inverting only
  /// the DISPLAY — what gets persisted is unchanged, including the
  /// apply-to-all overwrite of every show's own choice.
  bool hideNextEpisode;

  bool showContinueWatching;
  bool showSearchBar;

  void setAutoPlayNext(bool v) {
    autoPlayNext = v;
    unawaited(repository.setAutoPlayNext(v));
    notifyListeners();
  }

  void setSkipMode(SkipMode v) {
    skipMode = v;
    unawaited(repository.setSkipMode(v));
    notifyListeners();
  }

  void setMissingEnabled(bool v) {
    missingEnabled = v;
    unawaited(repository.setMissingEnabled(v));
    notifyListeners();
  }

  void setMinSkipLength(int seconds) {
    minSkipLength = Duration(
      seconds: seconds.clamp(0, minSkipLengthMax.inSeconds),
    );
    unawaited(repository.setMinSkipLength(minSkipLength));
    notifyListeners();
  }

  void setCorroborateSkips(bool v) {
    corroborateSkips = v;
    unawaited(repository.setCorroborateSkips(v));
    notifyListeners();
  }

  void setHideNextEpisode(bool v) {
    hideNextEpisode = v;
    unawaited(repository.setHideNextEpisode(v));
    notifyListeners();
  }

  void setShowContinueWatching(bool v) {
    showContinueWatching = v;
    unawaited(repository.setShowContinueWatching(v));
    notifyListeners();
  }

  void setShowSearchBar(bool v) {
    showSearchBar = v;
    unawaited(repository.setShowSearchBar(v));
    notifyListeners();
  }

  /// False while the field holds something unparseable, so the row can show its
  /// error.
  bool thresholdValid = true;

  /// Persist ONLY valid values — an invalid entry shows the error and is never
  /// written, so the stored value can't go to garbage.
  void editThreshold(String raw) {
    final parsed = parseWatchedThreshold(raw);
    thresholdValid = parsed != null;
    if (parsed != null) {
      watchedThreshold = parsed;
      unawaited(repository.setWatchedThreshold(parsed));
    }
    notifyListeners();
  }

  /// Normalize on commit so a half-typed/invalid entry snaps back to the last
  /// valid value (no lingering garbage).
  void commitThreshold() {
    thresholdController.text = formatWatchedThreshold(watchedThreshold);
    thresholdValid = true;
    notifyListeners();
  }

  @override
  void dispose() {
    thresholdController.dispose();
    super.dispose();
  }
}
