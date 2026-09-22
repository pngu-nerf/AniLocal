import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/source_descriptor.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/library_services.dart';
import 'package:anilocal/ui/scan_control.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/sources_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_fix_match.dart';
import 'fake_library_repository.dart';
import 'fake_settings.dart';

/// A show-preferences repository nothing in the test reads.
class NoPrefs extends Fake implements ShowPreferencesRepository {}

/// The services bundle a screen test needs: the one fake repo behind every
/// interface, a real (idle) playback controller, a settings bundle with
/// whatever source lists the ⚙ window should show, and the folder-health
/// notifiers a test may want to drive. Two screen tests each built this;
/// this is the one.
LibraryServices testLibraryServices(
  FakeLibraryRepository repo, {
  List<SourceDescriptor> metadata = const [],
  List<SourceDescriptor> skip = const [],
  ValueNotifier<Set<String>>? missing,
  ValueNotifier<List<String>>? denied,
  String? Function(String)? categoryLabelOf,
}) {
  final missingN = missing ?? ValueNotifier<Set<String>>(const {});
  final deniedN = denied ?? ValueNotifier<List<String>>(const []);
  final label = categoryLabelOf ?? (_) => null;
  return LibraryServices(
    repository: repo,
    fixMatch: const FakeFixMatch(),
    watchState: repo,
    sourceSelection: repo,
    watchOrder: repo,
    missingEpisodes: repo,
    showPreferences: NoPrefs(),
    settings: const FakeSettings(),
    playback: PlaybackController(resolver: repo),
    scan: ScanControl(),
    missingFolderPaths: missingN,
    accessIssues: deniedN,
    categoryLabelOf: label,
    unmatchedCount: ValueNotifier<int>(0),
    settingsActions: SettingsActions(
      sources: SourcesActions(
        repository: repo,
        onAddFolder: () async => (added: false, deniedLabel: null),
        onOpenAccessSettings: () async => false,
        scanning: ValueNotifier<bool>(false),
        missingFolderPaths: missingN,
        accessIssues: deniedN,
        categoryLabelOf: label,
      ),
      metadataSources: metadata,
      skipSources: skip,
      onRefreshMetadata: () async =>
          const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
      scanning: ValueNotifier<bool>(false),
    ),
  );
}
