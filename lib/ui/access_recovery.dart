import 'package:flutter/material.dart';

/// Written path shown in every access-recovery surface, so a stale deep-link
/// never strands the user.
const String kFilesAndFoldersPath =
    'System Settings → Privacy & Security → Files and Folders';

/// Contextual recovery, shown right after an add hits a denied category.
Future<void> showAccessDeniedDialog(
  BuildContext context,
  String label,
  Future<bool> Function() onOpenSettings,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Folder access needed'),
      content: Text(
        "AniLocal can't access $label.\n\n"
        'Enable AniLocal in $kFilesAndFoldersPath, then sync metadata.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            await onOpenSettings();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('Open Settings'),
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
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      leading: Icon(Icons.lock_outline, color: scheme.onErrorContainer),
      content: Text(
        "Can't access ${labels.join(', ')}. "
        'Enable AniLocal in $kFilesAndFoldersPath.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
      actions: [
        TextButton(onPressed: onRescan, child: const Text('Sync metadata')),
        TextButton(
          onPressed: () => onOpenSettings(),
          child: const Text('Open Settings'),
        ),
      ],
    );
  }
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
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: scheme.secondaryContainer,
      leading: Icon(Icons.link_off, color: scheme.onSecondaryContainer),
      content: Text(
        "${labels.join(', ')} isn't connected. Reconnect it to access this "
        'library, then sync metadata.',
        style: TextStyle(color: scheme.onSecondaryContainer),
      ),
      actions: [
        TextButton(onPressed: onRescan, child: const Text('Sync metadata')),
      ],
    );
  }
}
