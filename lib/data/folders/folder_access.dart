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

/// The three distinct readability conditions a library folder can be in. A
/// failed read is NOT automatically a permission problem — an unplugged drive
/// or offline NAS is a different condition with a different fix.
enum FolderAccessState {
  /// Readable — freely, or folder-wide access is held.
  accessible,

  /// The path/mount doesn't exist: an unplugged external drive or offline NAS.
  /// Recoverable by reconnecting (no Settings interaction); the folder is a
  /// valid library that's merely offline right now — never forget it.
  missing,

  /// The path exists but reading is blocked (TCC / EPERM / EACCES) — the
  /// Settings → Files-and-Folders recovery flow.
  denied,
}

/// Outcome of ensuring folder-wide access to a (possibly TCC-protected) folder.
class FolderAccessResult {
  const FolderAccessResult._(this.categoryLabel, this.state);

  /// The folder isn't under a TCC-protected category (freely readable).
  const FolderAccessResult.notApplicable()
    : this._(null, FolderAccessState.accessible);

  /// Folder-wide access to [categoryLabel] is held (clears any prior issue).
  const FolderAccessResult.granted(String categoryLabel)
    : this._(categoryLabel, FolderAccessState.accessible);

  /// [categoryLabel]'s mount/path doesn't exist — reconnect to recover.
  const FolderAccessResult.missing(String categoryLabel)
    : this._(categoryLabel, FolderAccessState.missing);

  /// Access to [categoryLabel] was denied (drives the Settings recovery UX).
  const FolderAccessResult.denied(String categoryLabel)
    : this._(categoryLabel, FolderAccessState.denied);

  /// Human label of the category/volume, or null when not category-protected.
  final String? categoryLabel;
  final FolderAccessState state;

  bool get isDenied => state == FolderAccessState.denied;
  bool get isMissing => state == FolderAccessState.missing;
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
