import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../diagnostics/app_log.dart';
import '../../domain/models/cache_footprint.dart';
import '../../domain/models/identified_episode.dart';
import '../../domain/models/refresh_summary.dart';
import '../../domain/models/source_descriptor.dart';
import '../../domain/repositories/show_preferences_repository.dart';
import '../metadata_failure_message.dart';
import '../widgets/notices.dart';
import 'sources_actions.dart';

/// The one sentence every mid-scan-disabled control says.
const String kWaitForScanTooltip = 'Wait for the scan to finish';

/// What Settings › Maintenance needs to name, measure and reset the data
/// folder. Closures from the composition root, so the UI holds no path logic
/// and walks no directory; each is nullable because a test has no folder,
/// and the rows then say so (a disabled Reveal, "Not available") rather than
/// pretending.
class MaintenanceActions {
  const MaintenanceActions({
    required this.dataPath,
    required this.measureFootprint,
    required this.resetCache,
    required this.scanning,
  });

  /// No folder behind the rows — the shape every test uses.
  const MaintenanceActions.absent()
    : dataPath = null,
      measureFootprint = null,
      resetCache = null,
      scanning = const AlwaysStoppedAnimation<bool>(false);

  /// The data folder, as a path the user can read and Reveal.
  final String? dataPath;

  /// Its size, measured off the UI isolate.
  final Future<CacheFootprint> Function()? measureFootprint;

  /// Set the cache aside; returns where it went. The app must quit after.
  final Future<String> Function()? resetCache;

  /// The reset is refused while a scan runs — the scan is writing the very
  /// database the reset closes.
  final ValueListenable<bool> scanning;
}

/// The app-wide half of what the Settings window needs, built ONCE at the
/// composition root and handed down as a single object. Which sources this
/// build ships and how metadata is refreshed do not depend on which screen
/// opened the window, so no screen assembles them — the bundle a screen hands
/// the window is minted in exactly one place, [forScreen], and the screen
/// supplies only the hooks that genuinely differ per entry point.
///
/// Structural rather than a convention: the show page used to build its own
/// [SettingsDialogActions] and left the two source lists at their defaults, so
/// Settings › Sources rendered EMPTY from two of the window's three
/// doors. Two things make that impossible to repeat: [SettingsDialogActions]
/// has a private constructor, and the two lists here have NO default — a
/// caller that forgets them does not compile.
class SettingsActions {
  const SettingsActions({
    required this.sources,
    required this.metadataSources,
    required this.skipSources,
    required this.onRefreshMetadata,
    required this.scanning,
    required this.showPreferences,
    required this.maintenance,
  });

  /// True while a scan runs; Refresh metadata is disabled then (the fill path
  /// would refuse it anyway — this makes the row say so instead of failing).
  final ValueListenable<bool> scanning;

  /// The data folder's name, size and reset — see [MaintenanceActions].
  final MaintenanceActions maintenance;

  /// Per-show preferences, read (never written) by the window: the Next
  /// episode master switch asks how many shows carry their own choice before
  /// it overwrites them. The interface only — seam #1 holds.
  final ShowPreferencesRepository showPreferences;

  /// Everything the Sources tab needs. One object rather than three more
  /// threaded callbacks — see [SourcesActions].
  final SourcesActions sources;

  /// Every metadata source this build ships, in built-in order. Descriptors,
  /// not providers — the UI never sees a `MetadataProvider` (seam #1).
  final List<SourceDescriptor> metadataSources;

  /// Every skip source this build ships, in built-in order.
  final List<SourceDescriptor> skipSources;

  /// Re-fetch metadata (ids + skip data) for cached series. Returns counts.
  final Future<RefreshSummary> Function() onRefreshMetadata;

  /// Complete the bundle with this screen's own hooks.
  SettingsDialogActions forScreen({
    required VoidCallback onRefreshed,
    required ValueListenable<int> unmatchedCount,
    required Future<List<IdentifiedEpisode>> Function() loadUnmatched,
    required Future<void> Function(IdentifiedEpisode file) onFixMatch,
  }) => SettingsDialogActions._(
    sources: sources,
    metadataSources: metadataSources,
    skipSources: skipSources,
    onRefreshMetadata: onRefreshMetadata,
    onRefreshed: onRefreshed,
    unmatchedCount: unmatchedCount,
    loadUnmatched: loadUnmatched,
    onFixMatch: onFixMatch,
    scanning: scanning,
    showPreferences: showPreferences,
    maintenance: maintenance,
  );
}

/// What the Settings window consumes: the app-wide [SettingsActions] plus the
/// few per-screen hooks — "reload THIS screen", this screen's unmatched count,
/// where "open unmatched" navigates. Only [SettingsActions.forScreen] builds
/// one. Every actual setting comes from the injected `SettingsRepository`.
class SettingsDialogActions {
  const SettingsDialogActions._({
    required this.sources,
    this.metadataSources = const [],
    this.skipSources = const [],
    required this.onRefreshMetadata,
    required this.onRefreshed,
    required this.unmatchedCount,
    required this.loadUnmatched,
    required this.onFixMatch,
    required this.scanning,
    required this.showPreferences,
    required this.maintenance,
  });

  /// See [SettingsActions.scanning].
  final ValueListenable<bool> scanning;

  /// See [SettingsActions.maintenance].
  final MaintenanceActions maintenance;

  /// See [SettingsActions.showPreferences].
  final ShowPreferencesRepository showPreferences;

  /// Everything the Sources tab needs. One object rather than three more
  /// threaded callbacks — see [SourcesActions].
  final SourcesActions sources;

  /// Every metadata source this build ships, in built-in order. Descriptors,
  /// not providers — the UI never sees a `MetadataProvider` (seam #1).
  final List<SourceDescriptor> metadataSources;

  /// Every skip source this build ships, in built-in order.
  final List<SourceDescriptor> skipSources;

  /// Re-fetch metadata (ids + skip data) for cached series. Returns counts.
  final Future<RefreshSummary> Function() onRefreshMetadata;

  /// Called after a successful refresh so the opening screen can reload.
  final VoidCallback onRefreshed;

  /// Confirmed-unmatched file count, LIVE — the Unmatched category's label
  /// and the Library row read it, and the panel reloads its list when it
  /// changes.
  final ValueListenable<int> unmatchedCount;

  /// The unmatched files themselves, for the Unmatched category.
  final Future<List<IdentifiedEpisode>> Function() loadUnmatched;

  /// Open fix-match for one file. The window has been closed by the time this
  /// runs (fix-match is a page); the hook reloads the opening screen after.
  final Future<void> Function(IdentifiedEpisode file) onFixMatch;
}

/// Re-fetch metadata + skip data for cached series (no scan, no data loss).
Future<void> refreshMetadata(
  BuildContext dialogContext,
  SettingsDialogActions actions,
) async {
  // Capture the app-level messenger AND the error colour before popping the
  // window — dialogContext is defunct once it's gone.
  final messenger = ScaffoldMessenger.of(dialogContext);
  Navigator.of(dialogContext).pop();
  showNoticeOn(messenger, 'Refreshing metadata…', replace: true);
  try {
    final r = await actions.onRefreshMetadata();
    final failure = r.failure;
    if (failure == null) {
      showNoticeOn(
        messenger,
        'Refreshed ${r.seriesRefreshed} shows · '
        '${r.skipsFetched} skip sets fetched'
        '${r.skipLookupsFailed > 0 ? ' · ${r.skipLookupsFailed} skip lookups failed, will retry' : ''}',
        replace: true,
      );
    } else {
      // An unreachable metadata service is a FAILED refresh, not a refresh
      // of zero shows: reporting success here sent the user hunting for a
      // local bug during an AniList outage.
      showNoticeOn(
        messenger,
        '⚠ ${metadataFailureCause(failure)} Your metadata was left untouched.',
        duration: kNoticeLong,
        replace: true,
        problem: true,
      );
    }
    actions.onRefreshed();
  } catch (e) {
    showNoticeOn(
      messenger,
      'Refresh failed. ${userFacingMessage(e)}',
      duration: kNoticeLong,
      replace: true,
    );
    AppLog.error('Refresh failed', error: e);
  }
}
