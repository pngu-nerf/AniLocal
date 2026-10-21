import 'package:flutter/material.dart';

import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/guarded.dart';
import '../../widgets/notices.dart';
import '../setting_row.dart';
import '../settings_actions.dart';
import '../settings_model.dart';

/// Maintenance: the upkeep actions — things done to the library or the
/// settings rather than settings about them. Nothing here is a preference,
/// and everything that cannot be undone asks first.
class MaintenancePanel extends StatelessWidget {
  const MaintenancePanel({
    super.key,
    required this.model,
    required this.actions,
  });

  final SettingsModel model;
  final SettingsDialogActions actions;

  Future<void> _resetSettings(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Reset all settings?',
      body:
          'Every setting goes back to its default, including the source '
          'order and each show\'s own "Next episode" choice. Your library, '
          'watch progress and fix-matches are kept.',
      confirmLabel: 'Reset to defaults',
    );
    if (!ok || !context.mounted) return;
    await guarded(
      'reset settings',
      () async {
        await model.resetToDefaults();
        if (context.mounted) showNotice(context, 'Settings reset.');
      },
      onError: (e) {
        if (context.mounted) showWriteFailed(context, e);
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Metadata',
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: actions.scanning,
            builder: (context, scanning, _) => SettingRow(
              label: 'Refresh metadata',
              // A scan and a refresh share the fill path and cannot overlap;
              // the row says so instead of failing with an error.
              subtitle: scanning
                  ? kWaitForScanTooltip
                  : 'Re-fetch show information and intro / outro timings',
              info:
                  'Re-fetches metadata for shows already in the cache, by id, '
                  'and fills in any missing intro/outro skip data.\n\n'
                  'This is not a rescan: no files are read, and it never '
                  'touches your fix-matches or watch progress.',
              onTap: scanning ? null : () => refreshMetadata(context, actions),
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
        title: 'Reset',
        children: [
          SettingRow(
            label: 'Reset settings',
            subtitle: 'Every setting back to its default.',
            info:
                'Playback, display, skip and source settings return to how '
                'AniLocal ships, and every show\'s own "Next episode" choice '
                'is cleared.\n\n'
                'Your library, watch progress, fix-matches and any client IDs '
                'you pasted are kept.',
            control: XpButton(
              icon: Icons.restart_alt,
              label: 'Reset…',
              onPressed: () => _resetSettings(context),
            ),
          ),
        ],
      ),
    ],
  );
}
