import 'dart:async';

import 'package:flutter/material.dart';

import '../../../diagnostics/app_log.dart';
import '../../../diagnostics/diagnostics.dart';
import '../../../domain/models/cache_footprint.dart';
import '../../library/library_states.dart';
import '../../metadata_failure_message.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/guarded.dart';
import '../../widgets/notices.dart';
import '../../widgets/xp_dialog.dart';
import '../../window_chrome.dart';
import '../setting_row.dart';
import '../settings_actions.dart';
import '../settings_model.dart';

/// Maintenance: the upkeep actions — things done to the library, the data
/// folder or the settings rather than settings about them. Nothing here is a
/// preference, and everything that cannot be undone asks first.
class MaintenancePanel extends StatefulWidget {
  const MaintenancePanel({
    super.key,
    required this.model,
    required this.actions,
  });

  final SettingsModel model;
  final SettingsDialogActions actions;

  @override
  State<MaintenancePanel> createState() => _MaintenancePanelState();
}

class _MaintenancePanelState extends State<MaintenancePanel> {
  MaintenanceActions get _maintenance => widget.actions.maintenance;

  /// Measured once per window (the panel stays mounted across tab switches).
  /// Information fails NEUTRAL: until the number lands the row says
  /// "Measuring…", never a stale figure.
  CacheFootprint? _footprint;
  Object? _sizeError;

  @override
  void initState() {
    super.initState();
    final measure = _maintenance.measureFootprint;
    if (measure == null) return;
    unawaited(
      guarded(
        'cache size',
        () async {
          final footprint = await measure();
          if (mounted) setState(() => _footprint = footprint);
        },
        onError: (e) {
          if (mounted) setState(() => _sizeError = e);
        },
      ),
    );
  }

  String get _sizeText {
    if (_maintenance.measureFootprint == null) return 'Not available';
    final error = _sizeError;
    if (error != null) return "Couldn't measure. ${userFacingMessage(error)}";
    final f = _footprint;
    if (f == null) return 'Measuring…';
    return '${formatBytes(f.totalBytes)} — '
        'database ${formatBytes(f.databaseBytes)} · '
        'covers ${formatBytes(f.artBytes)} · '
        'logs ${formatBytes(f.logsBytes)}'
        '${f.otherBytes > 0 ? ' · other ${formatBytes(f.otherBytes)}' : ''}';
  }

  Future<void> _resetSettings() async {
    final ok = await confirmAction(
      context,
      title: 'Reset all settings?',
      body:
          'Every setting goes back to its default, including the source '
          'order and each show\'s own "Next episode" choice. Your library, '
          'watch progress and fix-matches are kept.',
      confirmLabel: 'Reset to defaults',
    );
    if (!ok || !mounted) return;
    await guarded(
      'reset settings',
      () async {
        await widget.model.resetToDefaults();
        if (mounted) showNotice(context, 'Settings reset.');
      },
      onError: (e) {
        if (mounted) showWriteFailed(context, e);
      },
    );
  }

  /// Ask, set the cache aside, then hold the user at a quit prompt. The
  /// prompt is pushed OVER the Settings window rather than replacing it: the
  /// database is closed by then, so nothing underneath may be touched again,
  /// and a prompt that cannot be dismissed is what guarantees that.
  Future<void> _resetCache() async {
    final reset = _maintenance.resetCache;
    if (reset == null) return;
    final ok = await confirmAction(
      context,
      title: 'Reset library cache?',
      body:
          'This moves the library index aside and quits AniLocal. You lose '
          'watch progress, fix-matches, hidden episodes, per-show choices and '
          'every setting, and your folders will need to be added and scanned '
          'again.\n\n'
          'Your video files are not touched, and the old index is kept next '
          'to the new one.',
      // The default Cancel: two long labels overflow the dialog's action row.
      confirmLabel: 'Reset and quit',
    );
    if (!ok || !mounted) return;
    final String moved;
    try {
      moved = await reset();
    } catch (e, stack) {
      AppLog.error('Cache reset failed', error: e, stack: stack);
      if (mounted) showFailure(context, "Couldn't reset.", e);
      return;
    }
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: XpDialog(
            title: 'Library cache reset',
            content: Text(cacheResetMovedMessage(moved)),
            actions: [
              XpButton(
                lit: true,
                icon: Icons.power_settings_new,
                label: 'Quit AniLocal',
                onPressed: () => unawaited(WindowChrome.quit()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataPath = _maintenance.dataPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Metadata',
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: widget.actions.scanning,
              builder: (context, scanning, _) => SettingRow(
                label: 'Refresh metadata',
                // A scan and a refresh share the fill path and cannot
                // overlap; the row says so instead of failing with an error.
                subtitle: scanning
                    ? kWaitForScanTooltip
                    : 'Re-fetch show information and intro / outro timings',
                info:
                    'Re-fetches metadata for shows already in the cache, by '
                    'id, and fills in any missing intro/outro skip data.\n\n'
                    'This is not a rescan: no files are read, and it never '
                    'touches your fix-matches or watch progress.',
                onTap: scanning
                    ? null
                    : () => refreshMetadata(context, widget.actions),
                control: Icon(
                  Icons.cloud_sync_outlined,
                  size: 16,
                  color: scanning ? Xp.textFaint : Xp.textDim,
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Data',
          children: [
            SettingRow(
              label: 'Data folder',
              subtitle: dataPath ?? 'Not available',
              info:
                  'The library index, cover images, the log and the id map, '
                  'in one folder. Back it up to keep watch progress and '
                  'fix-matches; nothing in it is your video.',
              control: XpButton(
                icon: Icons.folder_open_outlined,
                label: 'Reveal',
                onPressed: dataPath == null
                    ? null
                    : () => fireAndForget(
                        'reveal data folder',
                        () => Diagnostics.revealPath(dataPath),
                      ),
              ),
            ),
            SettingRow(
              label: 'Size',
              subtitle: _sizeText,
              info:
                  'Measured when this page opens. Covers are the bulk of it; '
                  'the index grows with the number of files, the log is '
                  'capped and rotates.',
            ),
          ],
        ),
        SettingsGroup(
          title: 'Reset',
          children: [
            SettingRow(
              label: 'Reset settings',
              subtitle: 'Every setting back to its default.',
              info:
                  'Playback, display, skip and source settings return to how '
                  'AniLocal ships, and every show\'s own "Next episode" '
                  'choice is cleared.\n\n'
                  'Your library, watch progress, fix-matches and any client '
                  'IDs you pasted are kept.',
              control: XpButton(
                icon: Icons.restart_alt,
                label: 'Reset…',
                onPressed: _resetSettings,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _maintenance.scanning,
              builder: (context, scanning, _) => SettingRow(
                label: 'Reset library cache',
                subtitle: scanning
                    ? kWaitForScanTooltip
                    : 'Start over with an empty library.',
                info:
                    'Moves the library index aside and quits. The next launch '
                    'starts empty: you add your folders again and scan.\n\n'
                    'Lost: identifications and fix-matches, source pins, '
                    'watch progress, hidden episodes, per-show choices and '
                    'every setting. Nothing in your anime folders is '
                    'touched.\n\n'
                    'The old index and covers are kept beside the new ones as '
                    '"…broken-<date>", so they can be sent with a bug report '
                    'or put back by hand.',
                control: XpButton(
                  icon: Icons.restart_alt,
                  label: 'Reset…',
                  tooltip: scanning ? kWaitForScanTooltip : null,
                  onPressed: scanning || _maintenance.resetCache == null
                      ? null
                      : _resetCache,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
