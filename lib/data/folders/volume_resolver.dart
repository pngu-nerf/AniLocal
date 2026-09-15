import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:anilocal/data/cache/cache_database.dart' show LibraryFolders;

import 'package:anilocal/data/folders/folder_access.dart' show FolderAccess;

import 'package:anilocal/data/scanner/folder_scanner.dart' show FolderScanner;

import '../../diagnostics/app_log.dart';

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
  /// [plist] runs `diskutil info -plist <arg>` and returns its output, or null
  /// on any failure. Injectable so the caching rules are testable without
  /// diskutil; production uses the bounded process runner below.
  DiskutilVolumeResolver({Future<String?> Function(String arg)? plist})
    : _plist = plist ?? _diskutilPlist;

  final Future<String?> Function(String arg) _plist;

  static const _diskutil = '/usr/sbin/diskutil';
  final Map<String, String?> _mountByVolumeId = {};

  /// When each NEGATIVE answer ("not mounted") was recorded. A positive answer
  /// is kept for the instance's life — a mount point does not change while
  /// mounted — but a drive that is plugged back in during the session must be
  /// found again, so "not mounted" expires after [negativeTtl].
  final Map<String, DateTime> _negativeAt = {};
  static const Duration negativeTtl = Duration(seconds: 30);

  @override
  Future<VolumeInfo?> infoForPath(String path) async {
    // diskutil resolves a MOUNT ROOT, not an arbitrary subpath (a subdir of a
    // volume exits 1). Only removable/network volumes (under /Volumes) need UUID
    // identity; internal-disk paths are already stable, so we don't bind them
    // (null = "leave unbound; the stored path is its own stable identity").
    final root = _volumeRootOf(path);
    if (root == null) return null;
    final plist = await _plist(root);
    if (plist == null) return null;
    final uuid = diskutilPlistString(plist, 'VolumeUUID');
    final mount = diskutilPlistString(plist, 'MountPoint');
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
      final cached = _mountByVolumeId[volumeId];
      if (cached != null) {
        // A positive answer is trusted only while the mount point EXISTS. A
        // drive pulled mid-session used to be reported at its old mount for
        // the rest of the process, so the library never greyed until relaunch.
        final present = await Directory(
          cached,
        ).exists().timeout(const Duration(seconds: 5), onTimeout: () => false);
        if (present) return cached;
        _mountByVolumeId.remove(volumeId);
      } else {
        final since = _negativeAt[volumeId];
        final expired =
            since != null && DateTime.now().difference(since) >= negativeTtl;
        if (!expired) return null;
      }
    }
    final plist = await _plist(volumeId);
    final mount = plist == null
        ? null
        : diskutilPlistString(plist, 'MountPoint');
    // An unmounted-but-known volume reports an empty MountPoint -> treat as not
    // mounted. Cached (incl. null) to avoid re-shelling each read; a null
    // expires, see [negativeTtl].
    final resolved = (mount == null || mount.isEmpty) ? null : mount;
    _mountByVolumeId[volumeId] = resolved;
    if (resolved == null) {
      _negativeAt[volumeId] = DateTime.now();
    } else {
      _negativeAt.remove(volumeId);
    }
    return resolved;
  }

  /// `diskutil info` against a wedged network volume can block for a long
  /// time, and this runs on the READ path (every library load resolves each
  /// folder). Bounded, so a stuck volume degrades to "missing" instead of
  /// freezing the library screen.
  static const Duration _diskutilTimeout = Duration(seconds: 10);

  static Future<String?> _diskutilPlist(String arg) async {
    Process? process;
    try {
      // `Process.start`, not `run`: `run(...).timeout()` abandoned the child on
      // expiry, and every later library load against the same wedged volume
      // spawned another one. Killed on timeout, the process is gone too.
      process = await Process.start(_diskutil, ['info', '-plist', arg]);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final exit = await process.exitCode.timeout(_diskutilTimeout);
      if (exit != 0) return null;
      return await stdout;
    } on ProcessException catch (e) {
      // not macOS / diskutil missing -> caller falls back to null
      AppLog.warn('diskutil unavailable for $arg', error: e);
      return null;
    } on TimeoutException {
      // volume wedged -> treated as missing, never a hang
      process?.kill();
      AppLog.warn('diskutil timed out for $arg after $_diskutilTimeout');
      return null;
    }
  }
}

/// Pull a flat `<key>NAME</key><string>VALUE</string>` value from a diskutil
/// plist. Apple's plist shape is stable; a targeted match avoids an XML dep.
///
/// The value is XML-UNESCAPED: a volume named `Movies & TV` is written as
/// `Movies &amp; TV`, and returning that verbatim produced a mount point that
/// does not exist, so the folder resolved to "missing" after every remount.
/// Top-level and public so the parsing is testable without `diskutil`.
String? diskutilPlistString(String plist, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(plist);
  final raw = match?.group(1);
  return raw == null ? null : xmlUnescape(raw);
}

/// The five predefined XML entities plus numeric references — everything a
/// plist writer emits for text content.
String xmlUnescape(String text) => text
    .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
    })
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      return String.fromCharCode(int.parse(m.group(1)!));
    })
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

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
  // ASYNC, and bounded. This runs on the read path (every library load
  // resolves each folder) and `existsSync` on a wedged SMB/NFS mount blocked
  // the UI isolate for as long as the kernel took to give up — the very
  // freeze the diskutil timeout below was added to prevent, one line earlier.
  // A probe that does not answer in time reads as "missing", which is the
  // recoverable state the reconnect banner already handles.
  final present = await Directory(
    storedPath,
  ).exists().timeout(const Duration(seconds: 5), onTimeout: () => false);
  if (present) return storedPath;
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
String? volumeSubpathOf(String folderPath, String mountPoint) {
  if (folderPath == mountPoint) return '';
  if (folderPath.startsWith('$mountPoint/')) {
    return folderPath.substring(mountPoint.length + 1);
  }
  // Not under the reported mount: NULL, and the caller must not bind. This
  // used to return '' ("treat as the root"), which persisted a binding that
  // resolved the library folder to the whole volume after a remount — the
  // next scan walked the entire drive.
  return null;
}
