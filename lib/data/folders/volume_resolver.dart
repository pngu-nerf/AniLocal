import 'dart:io';

/// A volume's stable identity ([volumeId]) and where it is mounted RIGHT NOW
/// ([mountPoint]). The id survives remounts; the mount point does not.
class VolumeInfo {
  const VolumeInfo({required this.volumeId, required this.mountPoint});

  final String volumeId;
  final String mountPoint;
}

/// Resolves a removable/network volume's STABLE identity (a volume UUID) and its
/// CURRENT mount point, decoupling library identity from the mount-point name.
///
/// Why: macOS mounts a volume at `/Volumes/<name>`, but on a name collision it
/// becomes `/Volumes/<name> 1`, or the user renames it, or mounts it over SMB —
/// so the absolute path is NOT a stable identity. The UUID is. Behind an
/// interface (like [FolderScanner]/[FolderAccess]) so the platform mechanism is
/// swappable and tests can inject a fake.
abstract interface class VolumeResolver {
  /// The volume UUID + current mount point for the volume backing [path], or
  /// null when [path] isn't on a resolvable volume (internal disk paths, or
  /// `diskutil` unavailable). Used at scan/add time to BIND a folder to its
  /// volume.
  Future<VolumeInfo?> infoForPath(String path);

  /// The current mount point of the volume with [volumeId], or null if that
  /// volume isn't mounted right now (→ the folder is "missing", recoverable by
  /// reconnecting). Used at read/scan time to FOLLOW a remounted volume.
  Future<String?> mountPointForVolumeId(String volumeId);
}

/// macOS [VolumeResolver] backed by `diskutil info -plist`. Reads the volume
/// UUID + mount point from the property-list output. Memoizes UUID→mount within
/// the instance (cheap; a relaunch/rescan re-resolves), and never throws — any
/// failure (no diskutil, unknown volume, unmounted) surfaces as null.
class DiskutilVolumeResolver implements VolumeResolver {
  DiskutilVolumeResolver();

  static const _diskutil = '/usr/sbin/diskutil';
  final Map<String, String?> _mountByVolumeId = {};

  @override
  Future<VolumeInfo?> infoForPath(String path) async {
    // diskutil resolves a MOUNT ROOT, not an arbitrary subpath (a subdir of a
    // volume exits 1). Only removable/network volumes (under /Volumes) need UUID
    // identity; internal-disk paths are already stable, so we don't bind them
    // (null = "leave unbound; the stored path is its own stable identity").
    final root = _volumeRootOf(path);
    if (root == null) return null;
    final plist = await _diskutilPlist(root);
    if (plist == null) return null;
    final uuid = _plistString(plist, 'VolumeUUID');
    final mount = _plistString(plist, 'MountPoint');
    if (uuid == null || mount == null || mount.isEmpty) return null;
    _mountByVolumeId[uuid] = mount;
    return VolumeInfo(volumeId: uuid, mountPoint: mount);
  }

  /// The `/Volumes/<name>` mount root for [path], or null when [path] isn't on a
  /// mounted volume (internal disk). Mirrors the volume-category logic used for
  /// TCC access checks.
  String? _volumeRootOf(String path) {
    if (!path.startsWith('/Volumes/')) return null;
    final segs = path.split('/'); // ['', 'Volumes', '<name>', ...]
    if (segs.length < 3 || segs[2].isEmpty) return null;
    return '/Volumes/${segs[2]}';
  }

  @override
  Future<String?> mountPointForVolumeId(String volumeId) async {
    if (_mountByVolumeId.containsKey(volumeId)) {
      return _mountByVolumeId[volumeId];
    }
    final plist = await _diskutilPlist(volumeId);
    final mount = plist == null ? null : _plistString(plist, 'MountPoint');
    // An unmounted-but-known volume reports an empty MountPoint -> treat as not
    // mounted. Cache the result (incl. null) to avoid re-shelling each read.
    final resolved = (mount == null || mount.isEmpty) ? null : mount;
    _mountByVolumeId[volumeId] = resolved;
    return resolved;
  }

  Future<String?> _diskutilPlist(String arg) async {
    try {
      final result = await Process.run(_diskutil, ['info', '-plist', arg]);
      if (result.exitCode != 0) return null;
      return result.stdout as String;
    } on ProcessException {
      return null; // not macOS / diskutil missing -> caller falls back to null
    }
  }

  /// Pull a flat `<key>NAME</key><string>VALUE</string>` value from a diskutil
  /// plist. Apple's plist shape is stable; a targeted match avoids an XML dep.
  String? _plistString(String plist, String key) {
    final match = RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    return match?.group(1);
  }
}

/// Resolve a stored library folder to its CURRENT absolute path, transparently
/// following a volume that remounted under a different `/Volumes` name.
///
/// - Fast path: if the stored path still exists, use it (NO diskutil) — the
///   common case when nothing has moved, and the only path internal/unbound
///   folders ever take.
/// - Else, if bound to a volume, find that volume's current mount and rebase
///   ([volumeSubpath] is the folder's location within the volume).
/// - Null = the folder's volume isn't mounted (missing → the reconnect case).
Future<String?> resolveFolderPath({
  required String storedPath,
  required String? volumeId,
  required String? volumeSubpath,
  required VolumeResolver resolver,
}) async {
  if (Directory(storedPath).existsSync()) return storedPath;
  if (volumeId == null) return null; // internal path gone, or never bound
  final mount = await resolver.mountPointForVolumeId(volumeId);
  if (mount == null) return null; // volume not mounted
  return (volumeSubpath == null || volumeSubpath.isEmpty)
      ? mount
      : '$mount/$volumeSubpath';
}

/// Split an absolute file [absPath] into (owning folder, path-relative-to-it),
/// choosing the LONGEST matching [folderPaths] prefix (most specific when
/// folders nest). Pure string logic — the migration backfill and the fix-match
/// reverse lookup both use it. Falls back to (parent dir, basename) when no
/// folder matches, so a stray row is preserved rather than dropped.
({String folderPath, String relativePath}) rebaseToFolderRelative(
  String absPath,
  Iterable<String> folderPaths,
) {
  String? best;
  for (final f in folderPaths) {
    if (absPath == f || absPath.startsWith('$f/')) {
      if (best == null || f.length > best.length) best = f;
    }
  }
  if (best == null) {
    final i = absPath.lastIndexOf('/');
    return i <= 0
        ? (folderPath: '', relativePath: absPath)
        : (
            folderPath: absPath.substring(0, i),
            relativePath: absPath.substring(i + 1),
          );
  }
  final relative = absPath == best ? '' : absPath.substring(best.length + 1);
  return (folderPath: best, relativePath: relative);
}

/// The folder-relative subpath of [folderPath] within [mountPoint] (e.g.
/// `/Volumes/Anime/shows` under mount `/Volumes/Anime` → `shows`; the volume
/// root itself → `''`). Used to record [LibraryFolders.volumeSubpath] when
/// binding a folder to its volume.
String volumeSubpathOf(String folderPath, String mountPoint) {
  if (folderPath == mountPoint) return '';
  if (folderPath.startsWith('$mountPoint/')) {
    return folderPath.substring(mountPoint.length + 1);
  }
  return ''; // folder is not under the reported mount — treat as the root
}
