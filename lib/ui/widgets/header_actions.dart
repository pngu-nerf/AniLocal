import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// The app actions at the TOP-RIGHT of the title bar, as labelled tabs (icon +
/// title) that hang to the bar's bottom edge — Sources, Sync, Unmatched (only
/// when [unmatchedCount] > 0), Settings. Shared by EVERY screen with the header
/// (home + detail) so the header looks identical everywhere; only the back
/// button (a title-bar leading) differs between screens.
class HeaderActionsBar extends StatelessWidget {
  const HeaderActionsBar({
    super.key,
    required this.scanning,
    required this.unmatchedCount,
    required this.onFolders,
    required this.onUnmatched,
    required this.onScan,
    required this.onSettings,
  });

  final bool scanning;
  final int unmatchedCount;
  final Future<void> Function() onFolders;
  final VoidCallback onUnmatched;
  final Future<void> Function() onScan;
  // VoidCallback so both home's (Future-returning) and detail's (void) settings
  // openers assign — a `() => Future` is assignable to `() => void`.
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    // Labels only when the bar is wide enough to fit them alongside the
    // fixed-width VFD display in the left cluster; otherwise the tabs collapse
    // to icons. ~760 clears the display + traffic-light inset + labels.
    final showLabel = MediaQuery.sizeOf(context).width >= 760;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scanning) ...[
          const Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Xp.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        XpTitleTab(
          icon: Icons.folder_open,
          label: 'Sources',
          tooltip: 'Media sources',
          showLabel: showLabel,
          onPressed: onFolders,
        ),
        XpTitleTab(
          icon: Icons.sync,
          label: 'Sync',
          tooltip: scanning ? 'Syncing…' : 'Sync metadata',
          showLabel: showLabel,
          onPressed: scanning ? null : onScan,
        ),
        if (unmatchedCount > 0)
          XpTitleTab(
            icon: Icons.help_outline,
            label: 'Unmatched',
            tooltip: 'Unmatched files ($unmatchedCount)',
            showLabel: showLabel,
            onPressed: onUnmatched,
          ),
        XpTitleTab(
          icon: Icons.settings,
          label: 'Settings',
          tooltip: 'Settings',
          showLabel: showLabel,
          onPressed: onSettings,
        ),
      ],
    );
  }
}
