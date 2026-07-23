import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models/skip_mode.dart';

/// The largest watched-threshold the min:sec input accepts (9:59).
const watchedThresholdMax = Duration(minutes: 9, seconds: 59);

/// The default watched-threshold on first run — ~a typical ED/credits length,
/// so the old proportional-90% behavior is roughly preserved.
const watchedThresholdDefault = Duration(seconds: 90);

/// Parse a `m:ss` watched-threshold entry, or null if invalid. Rejects
/// non-numeric input, seconds ≥ 60, values past [watchedThresholdMax] (9:59),
/// and anything not shaped `minutes:seconds`. Pure, so it's unit-testable — the
/// single gate that keeps a blank/garbage value from ever being persisted.
Duration? parseWatchedThreshold(String input) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})\s*$').firstMatch(input);
  if (m == null) return null;
  final minutes = int.parse(m.group(1)!);
  final seconds = int.parse(m.group(2)!);
  if (seconds >= 60) return null;
  final total = Duration(minutes: minutes, seconds: seconds);
  if (total > watchedThresholdMax) return null;
  return total; // Duration can't be negative from non-negative parts.
}

/// Format a watched-threshold as `m:ss` (e.g. 90s → "1:30", zero → "0:00").
String formatWatchedThreshold(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The callbacks + loaders the shared app Settings dialog needs, so the homepage
/// and the detail page open the IDENTICAL dialog (single source of truth).
class SettingsActions {
  const SettingsActions({
    required this.loadAutoPlayNext,
    required this.setAutoPlayNext,
    required this.loadSkipMode,
    required this.setSkipMode,
    required this.loadWatchedThreshold,
    required this.setWatchedThreshold,
    required this.loadMissingEnabled,
    required this.setMissingEnabled,
    required this.onRefreshMetadata,
    required this.onRefreshed,
    required this.loadUnmatchedCount,
    required this.onOpenUnmatched,
    required this.onOpenSources,
    required this.loadHideNextEpisode,
    required this.setHideNextEpisode,
    required this.loadShowContinueWatching,
    required this.setShowContinueWatching,
    required this.loadShowSearchBar,
    required this.setShowSearchBar,
  });

  final Future<bool> Function() loadAutoPlayNext;
  final Future<void> Function(bool enabled) setAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;
  final Future<void> Function(SkipMode mode) setSkipMode;

  /// Watched-threshold as an absolute time-from-end (0:00 = auto-watched off);
  /// the single value ALL watched-marking consumers read.
  final Future<Duration> Function() loadWatchedThreshold;
  final Future<void> Function(Duration value) setWatchedThreshold;

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

  /// Open the Sources (library folders) page — the same page the header opens.
  final VoidCallback onOpenSources;

  /// GLOBAL "Hide Next Episode". [setHideNextEpisode] is a master apply-to-all:
  /// it persists the global flag AND overwrites every per-show value to match.
  final Future<bool> Function() loadHideNextEpisode;
  final Future<void> Function(bool hidden) setHideNextEpisode;

  /// GLOBAL homepage toggles: continue-watching sidebar + search bar visibility.
  final Future<bool> Function() loadShowContinueWatching;
  final Future<void> Function(bool show) setShowContinueWatching;
  final Future<bool> Function() loadShowSearchBar;
  final Future<void> Function(bool show) setShowSearchBar;
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
  var watchedThreshold = await actions.loadWatchedThreshold();
  var missingEnabled = await actions.loadMissingEnabled();
  var hideNext = await actions.loadHideNextEpisode();
  var showContinue = await actions.loadShowContinueWatching();
  var showSearch = await actions.loadShowSearchBar();
  final unmatchedCount = await actions.loadUnmatchedCount();
  if (!context.mounted) return;
  // Seed the min:sec field from the persisted value; disposed after the dialog.
  final thresholdController = TextEditingController(
    text: formatWatchedThreshold(watchedThreshold),
  );
  var thresholdValid = true;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Settings'),
      // Bounded width + scroll so the collapsible sections (expanded by default)
      // never overflow the dialog on a short window.
      content: SizedBox(
        width: 400,
        child: StatefulBuilder(
          builder: (context, setLocal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unmatched files — top level, always reachable.
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

                // --- Media Player -------------------------------------
                _Section(
                  title: 'Media Player',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto play episode'),
                      subtitle: const Text(
                        'When an episode ends, play the next one.',
                      ),
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
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(
                        'Duration from end to mark episode as watched',
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: thresholdController,
                        // Digits + a single colon; m:ss never exceeds 4 chars.
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
                          LengthLimitingTextInputFormatter(5),
                        ],
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'm:ss',
                          errorText: thresholdValid
                              ? null
                              : 'Enter m:ss (max 9:59)',
                        ),
                        // Persist ONLY valid values — an invalid entry shows the
                        // error and is never written, so the stored value can't
                        // go to garbage.
                        onChanged: (raw) {
                          final parsed = parseWatchedThreshold(raw);
                          setLocal(() => thresholdValid = parsed != null);
                          if (parsed != null) {
                            watchedThreshold = parsed;
                            actions.setWatchedThreshold(parsed);
                          }
                        },
                        // Normalize on commit so a half-typed/invalid entry snaps
                        // back to the last valid value (no lingering garbage).
                        onEditingComplete: () {
                          thresholdController.text = formatWatchedThreshold(
                            watchedThreshold,
                          );
                          setLocal(() => thresholdValid = true);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '0:00 turns off automatic watched-marking entirely.\n'
                        'Episodes shorter than this duration are marked watched '
                        'when opened.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),

                // --- Library ------------------------------------------
                _Section(
                  title: 'Library',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show / hide missing episodes'),
                      subtitle: const Text(
                        'Ghost tiles for gaps in a series; hide ones you '
                        'don’t want.',
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
                      leading: const Icon(Icons.folder_open),
                      title: const Text('Edit sources'),
                      subtitle: const Text('Add or reorder library folders'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        actions.onOpenSources();
                      },
                    ),
                  ],
                ),

                // --- Homepage -----------------------------------------
                _Section(
                  title: 'Homepage',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      isThreeLine: true,
                      title: const Text('Hide next episode'),
                      subtitle: const Text(
                        'Hides the next-episode button on every show. '
                        'Toggling this OVERWRITES each show’s individual '
                        'next-episode choice to match.',
                      ),
                      value: hideNext,
                      onChanged: (v) {
                        setLocal(() => hideNext = v);
                        actions.setHideNextEpisode(v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show / hide continue watching tab'),
                      value: showContinue,
                      onChanged: (v) {
                        setLocal(() => showContinue = v);
                        actions.setShowContinueWatching(v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show / hide search bar'),
                      value: showSearch,
                      onChanged: (v) {
                        setLocal(() => showSearch = v);
                        actions.setShowSearchBar(v);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
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
  thresholdController.dispose();
}

/// A collapsible settings section. COLLAPSED by default on every open (a fixed,
/// predictable arrangement — no persisted expand state to keep in sync).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 4),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      children: children,
    );
  }
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
