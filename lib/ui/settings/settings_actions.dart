import 'package:flutter/material.dart';

import '../../domain/models/source_descriptor.dart';
import '../../domain/models/refresh_summary.dart';
import '../metadata_failure_message.dart';
import 'sources_actions.dart';
import '../../diagnostics/app_log.dart';

/// The few NON-setting, per-screen hooks the Settings window needs (the settings
/// themselves come from the injected `SettingsRepository`). These genuinely
/// differ per entry point — "reload THIS screen", this screen's unmatched count,
/// where "open sources/unmatched" navigate — so they're passed in, while every
/// actual setting is single-source.
class SettingsDialogActions {
  const SettingsDialogActions({
    required this.sources,
    this.metadataSources = const [],
    this.skipSources = const [],
    required this.onRefreshMetadata,
    required this.onRefreshed,
    required this.loadUnmatchedCount,
    required this.onOpenUnmatched,
  });

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

  /// Current confirmed-unmatched file count (for the "Unmatched files" row).
  final Future<int> Function() loadUnmatchedCount;

  /// Navigate to the unmatched-files screen (the window is closed first).
  final VoidCallback onOpenUnmatched;
}

/// Re-fetch metadata + skip data for cached series (no scan, no data loss).
Future<void> refreshMetadata(
  BuildContext dialogContext,
  SettingsDialogActions actions,
) async {
  // Capture the app-level messenger AND the error colour before popping the
  // window — dialogContext is defunct once it's gone.
  final messenger = ScaffoldMessenger.of(dialogContext);
  final errorBackground = Theme.of(dialogContext).colorScheme.errorContainer;
  Navigator.of(dialogContext).pop();
  messenger
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text('Refreshing metadata…')));
  try {
    final r = await actions.onRefreshMetadata();
    final failure = r.failure;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        failure == null
            ? SnackBar(
                content: Text(
                  'Refreshed ${r.seriesRefreshed} series · '
                  '${r.skipsFetched} skip sets fetched',
                ),
              )
            : SnackBar(
                // An unreachable AniList is a FAILED refresh, not a refresh of
                // zero series: reporting success here sent the user hunting for
                // a local bug during an AniList outage.
                duration: const Duration(seconds: 8),
                backgroundColor: errorBackground,
                content: Text(
                  '⚠ ${metadataFailureCause(failure)} '
                  'Your metadata was left untouched.',
                ),
              ),
      );
    actions.onRefreshed();
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Refresh failed: $e — details are in Settings › About.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    AppLog.error('Refresh failed', error: e);
  }
}
