import 'package:flutter/material.dart';

import '../domain/models/skip_mode.dart';

/// The callbacks + loaders the shared app Settings dialog needs, so the homepage
/// and the detail page open the IDENTICAL dialog (single source of truth).
class SettingsActions {
  const SettingsActions({
    required this.loadAutoPlayNext,
    required this.setAutoPlayNext,
    required this.loadSkipMode,
    required this.setSkipMode,
    required this.loadMissingEnabled,
    required this.setMissingEnabled,
    required this.onRefreshMetadata,
    required this.onRefreshed,
    required this.loadUnmatchedCount,
    required this.onOpenUnmatched,
  });

  final Future<bool> Function() loadAutoPlayNext;
  final Future<void> Function(bool enabled) setAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;
  final Future<void> Function(SkipMode mode) setSkipMode;
  final Future<bool> Function() loadMissingEnabled;
  final Future<void> Function(bool enabled) setMissingEnabled;

  /// Re-fetch metadata (idMal + skip data) for cached series. Returns counts.
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

  /// Called after a successful refresh so the opening screen can reload.
  final VoidCallback onRefreshed;

  /// Current confirmed-unmatched file count (for the "Unmatched files" row).
  final Future<int> Function() loadUnmatchedCount;

  /// Navigate to the unmatched-files screen (the dialog is popped first).
  final VoidCallback onOpenUnmatched;
}

/// A settings-group caption strip (accent, uppercase) — the shared section
/// header used inside the dialog.
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

String skipModeLabel(SkipMode mode) => switch (mode) {
  SkipMode.off => 'No skip',
  SkipMode.button => 'Skip button',
  SkipMode.auto => 'Auto skip',
};

/// Open the shared app Settings dialog. Reachable from the homepage title bar
/// and the detail-page title bar; both pass a [SettingsActions] bundle.
Future<void> showAppSettingsDialog(
  BuildContext context,
  SettingsActions actions,
) async {
  var enabled = await actions.loadAutoPlayNext();
  var skipMode = await actions.loadSkipMode();
  var missingEnabled = await actions.loadMissingEnabled();
  final unmatchedCount = await actions.loadUnmatchedCount();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Settings'),
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Playback ---------------------------------------------
            const SettingsSection('Playback'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-play next episode'),
              subtitle: const Text('When an episode ends, play the next one.'),
              value: enabled,
              onChanged: (v) {
                setLocal(() => enabled = v);
                actions.setAutoPlayNext(v);
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 2),
              child: Text('Skip intro / outro'),
            ),
            for (final mode in SkipMode.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  mode == skipMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(skipModeLabel(mode)),
                onTap: () {
                  setLocal(() => skipMode = mode);
                  actions.setSkipMode(mode);
                },
              ),
            // --- Metadata ---------------------------------------------
            const SettingsSection('Metadata'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show missing episodes'),
              subtitle: const Text(
                'Ghost tiles for gaps in a series; hide ones you don’t want.',
              ),
              value: missingEnabled,
              onChanged: (v) {
                setLocal(() => missingEnabled = v);
                actions.setMissingEnabled(v);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Refresh metadata'),
              subtitle: const Text('Re-fetch idMal + skip data'),
              onTap: () => _refreshMetadata(dialogContext, actions),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.help_outline),
              title: const Text('Unmatched files'),
              subtitle: Text(
                unmatchedCount == 0
                    ? 'Nothing needs fixing'
                    : '$unmatchedCount file(s) we could not identify',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(dialogContext).pop();
                actions.onOpenUnmatched();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// Re-fetch metadata + skip data for cached series (no scan, no data loss).
Future<void> _refreshMetadata(
  BuildContext dialogContext,
  SettingsActions actions,
) async {
  // Capture the app-level messenger before popping the dialog.
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
