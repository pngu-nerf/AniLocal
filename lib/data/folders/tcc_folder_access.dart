import 'dart:io';

import 'folder_access.dart';

/// Provokes the macOS folder-wide TCC prompt by attempting to enumerate the
/// category root (Downloads/Documents/Desktop, or a removable volume root).
///
/// - undecided → the enumerate makes `tccd` show "AniLocal would like to access
///   your Downloads folder"; the call blocks until the user answers.
/// - allowed (now or previously) → enumerate succeeds → granted.
/// - denied (now or stored) → enumerate throws → denied. macOS will NOT
///   re-prompt after a denial, so the caller must guide the user to Settings.
///
/// In-memory cache of confirmed category roots avoids re-probing a granted
/// category within a session (provocation stays lazy + once).
class TccFolderAccess implements FolderAccess {
  TccFolderAccess({String? home})
    : _home = home ?? (Platform.environment['HOME'] ?? '');

  final String _home;
  final Set<String> _confirmed = {};

  @override
  Future<FolderAccessResult> ensureAccess(String folderPath) async {
    final cat = tccCategoryRoot(folderPath, _home);
    if (cat == null) return const FolderAccessResult.notApplicable();
    if (_confirmed.contains(cat.root)) {
      return FolderAccessResult.granted(cat.label);
    }
    try {
      // Enumerate the category root, reading at most one entry. The opendir is
      // what triggers TCC; an empty dir completes fine, a denial throws.
      await for (final _ in Directory(cat.root).list(followLinks: false)) {
        break;
      }
      _confirmed.add(cat.root);
      return FolderAccessResult.granted(cat.label);
    } on FileSystemException {
      // The read failed — but WHY matters. A missing mount (unplugged drive,
      // offline NAS) is "no such directory", NOT a permission denial: the
      // category root simply doesn't exist. Branch on which actually occurred
      // rather than treating every failure as access-denied. (A genuine TCC
      // denial leaves the well-known dir in place, so it still exists.)
      if (!Directory(cat.root).existsSync()) {
        return FolderAccessResult.missing(cat.label);
      }
      return FolderAccessResult.denied(cat.label);
    }
  }
}

/// Deep-link to the macOS privacy pane, with fallbacks. Tries the specific
/// Files-and-Folders pane, then the general Privacy & Security pane. Returns
/// false if both fail — the caller's message always also shows the written
/// path, so a stale link never strands the user.
Future<bool> openPrivacyFilesAndFoldersSettings() async {
  const urls = [
    'x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders',
    'x-apple.systempreferences:com.apple.preference.security?Privacy',
    'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension',
  ];
  for (final url in urls) {
    try {
      final result = await Process.run('open', [url]);
      if (result.exitCode == 0) return true;
    } on ProcessException {
      // try next
    }
  }
  return false;
}
