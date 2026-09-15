import 'dart:async';
import 'dart:io';

import '../../diagnostics/app_log.dart';
import 'folder_access.dart';
import 'volume_resolver.dart';

/// A library folder as the probe needs it: the stored path plus its volume
/// binding (both null for an internal-disk folder).
typedef FolderRef = ({String path, String? volumeId, String? volumeSubpath});

/// Whether [path] can be listed right now. Injected so the probe is testable
/// without a filesystem that misbehaves on cue.
typedef FolderReadable = Future<bool> Function(String path);

/// What one pass over the library folders found, rebuilt WHOLESALE every pass
/// so nothing goes stale: a folder that came back drops out of every set the
/// moment the next pass runs.
class FolderHealthReport {
  const FolderHealthReport({
    this.missingPaths = const {},
    this.missingLabels = const [],
    this.deniedLabels = const [],
  });

  /// Stored folder paths whose volume is not mounted — the greying key.
  final Set<String> missingPaths;

  /// Human labels (category or volume) of the missing folders — the
  /// reconnect banner. Sorted.
  final List<String> missingLabels;

  /// Labels of categories that are BOTH denied AND could not be read — the
  /// Files-and-Folders banner. Sorted.
  final List<String> deniedLabels;
}

/// Which library folders are reachable RIGHT NOW.
///
/// Runs at launch and at the start of every scan. Two rules it exists to
/// hold, both learnt from a walkthrough:
///
/// - **Every set is rebuilt from scratch, together.** The old pass mutated
///   the label lists folder by folder and rebuilt only the path set, so after
///   one folder lied the banner and the greying disagreed. Here one report
///   replaces all three, and a folder that throws is recorded as missing
///   rather than aborting the pass.
/// - **Denied means unreadable now.** A category grant (Downloads) can be
///   denied while the folder inside it reads fine through the picker's own
///   consent, and raising the banner for the grant alone showed "Can't
///   access Downloads" over a scan that worked. A label is denied only when
///   the folder itself cannot be listed.
class FolderHealthProbe {
  FolderHealthProbe({
    required this.resolver,
    required this.access,
    FolderReadable? readable,
  }) : _readable = readable ?? _canList;

  final VolumeResolver resolver;
  final FolderAccess access;
  final FolderReadable _readable;

  Future<FolderHealthReport> probe(Iterable<FolderRef> folders) async {
    final missingPaths = <String>{};
    final missingLabels = <String>{};
    final deniedLabels = <String>{};
    for (final f in folders) {
      try {
        final current = await resolveFolderPath(
          storedPath: f.path,
          volumeId: f.volumeId,
          volumeSubpath: f.volumeSubpath,
          resolver: resolver,
        );
        // Checked on the CURRENT mount so a volume that remounted under a
        // new name is not mistaken for missing; an unmounted one (null)
        // reports missing via its stored path's category.
        final result = await access.ensureAccess(current ?? f.path);
        final label = result.categoryLabel;
        if (current == null || result.isMissing) {
          missingPaths.add(f.path);
          if (label != null) missingLabels.add(label);
        } else if (result.isDenied && label != null) {
          if (!await _readable(current)) deniedLabels.add(label);
        }
      } catch (e, stack) {
        // A wedged mount or a probe that throws: the folder is not reachable,
        // which is what "missing" means — and the pass goes on.
        AppLog.warn(
          'Folder health: ${f.path} probe failed',
          error: e,
          stack: stack,
        );
        missingPaths.add(f.path);
      }
    }
    return FolderHealthReport(
      missingPaths: missingPaths,
      missingLabels: missingLabels.toList()..sort(),
      deniedLabels: deniedLabels.toList()..sort(),
    );
  }

  /// One directory read, bounded: a listing that does not answer in time is
  /// treated as readable (no banner on a guess).
  static Future<bool> _canList(String path) async {
    try {
      await Directory(path)
          .list(followLinks: false)
          .isEmpty
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
