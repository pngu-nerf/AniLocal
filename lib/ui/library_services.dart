import 'package:flutter/foundation.dart';

import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/show_preferences_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import '../playback/playback_controller.dart';
import 'settings/settings_actions.dart';

/// Everything a library screen reads and writes, as ONE object.
///
/// Built once at the composition root and handed down. Before this, nine
/// repositories and the settings bundle were threaded through five levels —
/// `AniLocalApp` → library → card → show page → theater — and the card took
/// eighteen required parameters of which it read six; the rest existed only
/// to be forwarded. That is the shape CLAUDE.md forbids for settings, applied
/// to everything else.
///
/// Interfaces only: a screen still sees a `LibraryRepository`, never the Drift
/// class behind it (seam #1). In production several of these are one object;
/// tests hand in whatever fakes the screen under test needs.
class LibraryServices {
  const LibraryServices({
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.missingEpisodes,
    required this.showPreferences,
    required this.settings,
    required this.settingsActions,
    required this.playback,
    required this.scanning,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (the missing-episodes feature). Named for what it
  /// holds: `missing` alone collided with the missing-FOLDER sets the library
  /// screen also carries.
  final MissingEpisodesRepository missingEpisodes;
  final ShowPreferencesRepository showPreferences;
  final SettingsRepository settings;

  /// The app-wide half of the Settings window (see [SettingsActions]).
  final SettingsActions settingsActions;

  /// The app-lifetime playback engine.
  final PlaybackController playback;

  /// Whether a scan is in flight, LIVE, for every header that shows the
  /// spinner and disables Scan. The show page and the theater used to
  /// hardcode `false`, so two taps from there started two scans over one
  /// database.
  final ValueNotifier<bool> scanning;
}
