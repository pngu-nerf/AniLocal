/// Access to a library folder, abstracted so the rest of the app resolves
/// folders through a token rather than a raw path string.
///
/// For an unsandboxed macOS app, the access grant to a protected folder
/// (Downloads/Documents/Desktop) comes from the user's native open-panel
/// selection — inferred consent recorded as a `com.apple.macl` xattr ON THE
/// FOLDER, which persists across relaunches. It does NOT come from owning the
/// path. So a [FolderAccessToken] is minted ONLY from a panel pick; there is no
/// code path that reaches a protected folder via a fabricated path.
///
/// (Security-scoped bookmarks are a no-op while unsandboxed, so the token wraps
/// a path today. If we ever sandbox, only this token + its resolver change —
/// nothing upstream knows the difference.)
class FolderAccessToken {
  const FolderAccessToken(this.path);

  final String path;
}

/// Opens the native folder open-panel — the ONLY place a [FolderAccessToken] is
/// created (the selection is what establishes the OS access grant). Returns
/// null if the user cancels.
abstract interface class FolderPicker {
  Future<FolderAccessToken?> pickFolder();
}

/// Outcome of ensuring folder-wide access to a TCC-protected category.
class FolderAccessResult {
  const FolderAccessResult._(this.categoryLabel, this.isDenied);

  /// The folder isn't under a TCC-protected category (freely readable).
  const FolderAccessResult.notApplicable() : this._(null, false);

  /// Folder-wide access to [categoryLabel] is held (clears any prior issue).
  const FolderAccessResult.granted(String categoryLabel)
    : this._(categoryLabel, false);

  /// Access to [categoryLabel] was denied (drives the recovery UX).
  const FolderAccessResult.denied(String categoryLabel)
    : this._(categoryLabel, true);

  /// Human label of the category, or null when not category-protected.
  final String? categoryLabel;
  final bool isDenied;
}

/// Ensures the app has folder-wide read access to a (possibly TCC-protected)
/// library folder. Kept behind this interface so the mechanism stays swappable
/// (today: provoke the macOS category prompt; a future sandboxed build could
/// resolve a security-scoped bookmark instead).
///
/// ADDITIVE by contract: this only attempts to *upgrade* to folder-wide access.
/// It never gates the scanner's per-folder reads — a folder already readable via
/// its own inferred-consent (macl) keeps working even if the category is denied.
abstract interface class FolderAccess {
  Future<FolderAccessResult> ensureAccess(String folderPath);
}

/// The TCC category root to probe for [path], plus a human label — or null when
/// [path] is not under a TCC-protected category (freely readable, no prompt).
/// Pure and testable; the home dir is injected.
({String root, String label})? tccCategoryRoot(String path, String home) {
  for (final name in const ['Downloads', 'Documents', 'Desktop']) {
    final root = '$home/$name';
    if (path == root || path.startsWith('$root/')) {
      return (root: root, label: name);
    }
  }
  if (path.startsWith('/Volumes/')) {
    final segs = path.split('/'); // ['', 'Volumes', '<name>', ...]
    if (segs.length >= 3 && segs[2].isNotEmpty) {
      return (root: '/Volumes/${segs[2]}', label: 'the volume “${segs[2]}”');
    }
  }
  return null;
}
