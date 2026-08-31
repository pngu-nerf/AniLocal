import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// The app actions at the TOP-RIGHT of the title bar, as labelled tabs (icon +
/// title) that hang to the bar's bottom edge — Sync, Unmatched (only when
/// [unmatchedCount] > 0), Settings. Sources is deliberately NOT here: it is a
/// settings category now, reached through ⚙ like every other setting, so the
/// header keeps ONE door into configuration rather than two. Shared by EVERY
/// screen with the header (home + detail + theater) so the header looks
/// identical everywhere; only the back button (a title-bar leading) differs.
class HeaderActionsBar extends StatelessWidget {
  const HeaderActionsBar({
    super.key,
    required this.scanning,
    required this.unmatchedCount,
    required this.onUnmatched,
    required this.onScan,
    required this.onSettings,
  });

  final bool scanning;
  final int unmatchedCount;
  final VoidCallback onUnmatched;
  final Future<void> Function() onScan;
  // VoidCallback so both home's (Future-returning) and detail's (void) settings
  // openers assign — a `() => Future` is assignable to `() => void`.
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    // Labels only when the bar is wide enough to fit them alongside the left
    // cluster and the centred VFD screen; otherwise the tabs collapse to icons
    // (which also hands the screen its room back). One shared signal — see
    // [XpTitleBar.showsLabels].
    final showLabel = XpTitleBar.showsLabels(context);
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
