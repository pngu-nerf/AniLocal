import 'package:flutter/material.dart';

import 'sources_actions.dart';

/// The few NON-setting, per-screen hooks the Settings window needs (the settings
/// themselves come from the injected `SettingsRepository`). These genuinely
/// differ per entry point — "reload THIS screen", this screen's unmatched count,
/// where "open sources/unmatched" navigate — so they're passed in, while every
/// actual setting is single-source.
class SettingsDialogActions {
  const SettingsDialogActions({
    required this.sources,
    required this.onRefreshMetadata,
    required this.onRefreshed,
    required this.loadUnmatchedCount,
    required this.onOpenUnmatched,
  });

  /// Everything the Sources tab needs. One object rather than three more
  /// threaded callbacks — see [SourcesActions].
  final SourcesActions sources;

  /// Re-fetch metadata (idMal + skip data) for cached series. Returns counts.
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

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
  // Capture the app-level messenger before popping the window.
  final messenger = ScaffoldMessenger.of(dialogContext);
  Navigator.of(dialogContext).pop();
  messenger
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text('Refreshing metadata…')));
  try {
    final r = await actions.onRefreshMetadata();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Refreshed ${r.seriesRefreshed} series · '
            '${r.skipsFetched} skip sets fetched',
          ),
        ),
      );
    actions.onRefreshed();
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
  }
}
