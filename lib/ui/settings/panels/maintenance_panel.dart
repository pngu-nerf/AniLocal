import 'package:flutter/material.dart';

import '../../theme/xp_tokens.dart';
import '../setting_row.dart';
import '../settings_actions.dart';

/// Maintenance: the upkeep actions — things done to the library rather than
/// settings about it. Nothing here is a preference.
class MaintenancePanel extends StatelessWidget {
  const MaintenancePanel({super.key, required this.actions});

  final SettingsDialogActions actions;

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
    ],
  );
}
