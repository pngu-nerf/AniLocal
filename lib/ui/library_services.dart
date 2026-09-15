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
import 'scan_control.dart';
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
    required this.scan,
    required this.missingFolderPaths,
    required this.accessIssues,
    required this.categoryLabelOf,
    required this.unmatchedCount,
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

  /// Scan state for every header — the running flag, the progress readout and
  /// Stop. One object, app-lifetime, so the show page and the theater see the
  /// same scan the library started (they used to hardcode `false`, so two
  /// taps from there started two scans over one database).
  final ScanControl scan;

  /// True while a scan runs — the flag every header disables its Scan on.
  ValueNotifier<bool> get scanning => scan.scanning;

  /// Library folder PATHS whose volume is not mounted right now. Written by
  /// the composition root's folder-health pass (at launch and on every scan);
  /// read by every screen that greys or blocks a file-dependent action.
  final ValueListenable<Set<String>> missingFolderPaths;

  /// TCC category labels ("Downloads", 'the volume "X"') whose access is
  /// currently DENIED — distinct from missing: the fix is System Settings,
  /// not a cable.
  final ValueListenable<List<String>> accessIssues;

  /// The TCC category label a folder path falls under, or null when it is
  /// freely readable. Supplied by the composition root so the UI can relate
  /// a folder to [accessIssues] without importing the data layer.
  final String? Function(String path) categoryLabelOf;

  /// CONFIRMED-unmatched files, LIVE: the library screen writes it from each
  /// snapshot; every header reads it. It used to travel as a push-time
  /// integer, so a scan from the player left the Unmatched tab wrong.
  final ValueNotifier<int> unmatchedCount;
}
