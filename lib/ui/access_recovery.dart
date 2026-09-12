import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/xp_banner.dart';
import 'widgets/xp_dialog.dart';

/// Written path shown in every access-recovery surface, so a stale deep-link
/// never strands the user.
const String kFilesAndFoldersPath =
    'System Settings › Privacy & Security › Files and Folders';

/// Contextual recovery, shown right after an add hits a denied category.
Future<void> showAccessDeniedDialog(
  BuildContext context,
  String label,
  Future<bool> Function() onOpenSettings,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => XpDialog(
      title: 'Folder access needed',
      content: Text(
        "AniLocal can't access $label.\n\n"
        'Enable AniLocal in $kFilesAndFoldersPath, then scan again.',
      ),
      actions: [
        XpButton(label: 'Later', onPressed: () => Navigator.of(ctx).pop()),
        XpButton(
          lit: true,
          label: 'Open Settings',
          onPressed: () async {
            await onOpenSettings();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ],
    ),
  );
}

/// Ambient recovery, shown while any watched folder's category is denied
/// (including a relaunch into a denied state) — never a silently-empty library.
class AccessBanner extends StatelessWidget {
  const AccessBanner({
    super.key,
    required this.labels,
    required this.onOpenSettings,
    required this.onRescan,
  });

  final List<String> labels;
  final Future<bool> Function() onOpenSettings;

  /// Null while a scan is already running: the button reads disabled.
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) => XpBanner(
    icon: Icons.lock_outline,
    iconColor: Xp.error,
    message:
        "Can't access ${labels.join(', ')}. "
        'Enable AniLocal in $kFilesAndFoldersPath.',
    actions: [
      XpButton(dense: true, label: 'Scan', onPressed: onRescan),
      XpButton(
        dense: true,
        label: 'Open Settings',
        onPressed: () => unawaited(onOpenSettings()),
      ),
    ],
  );
}

/// Ambient recovery for a library folder whose drive/mount is OFFLINE — a
/// connectivity problem, not a permission one. No Settings link (nothing is
/// broken there); reconnecting the drive + rescanning restores it, and the
/// folder is kept meanwhile (never forgotten).
class ReconnectBanner extends StatelessWidget {
  const ReconnectBanner({
    super.key,
    required this.labels,
    required this.onRescan,
  });

  final List<String> labels;

  /// Null while a scan is already running: the button reads disabled.
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) => XpBanner(
    icon: Icons.link_off,
    message:
        "${labels.join(', ')} isn't connected. Reconnect it to access this "
        'library, then scan again.',
    actions: [XpButton(dense: true, label: 'Scan', onPressed: onRescan)],
  );
}
