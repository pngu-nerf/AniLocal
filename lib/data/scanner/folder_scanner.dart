import 'dart:io';
import 'dart:isolate';
import '../../diagnostics/app_log.dart';
import '../paths.dart';

/// A file's identity fingerprint: what the scan compares to decide whether
/// the bytes changed. Plain values, so it crosses an isolate boundary.
typedef FileSig = ({int size, int modifiedMs});

/// Walks a library folder and finds video files. Behind an interface so the
/// traversal strategy is swappable and testable.
abstract class FolderScanner {
  const FolderScanner();

  /// Return absolute paths of video files under [folderPath] (recursive),
  /// sorted for stable ordering. Throws if the folder does not exist.
  Future<List<String>> findVideoFiles(String folderPath);

  /// Every video file under [folderPath] with its fingerprint, in one call.
  /// A file that vanishes between the listing and its stat is omitted. The
  /// default lists then stats inline (what a test double gets for free); the
  /// real scanner does both off the UI isolate. Throws like [findVideoFiles]
  /// when the root cannot be listed.
  Future<Map<String, FileSig>> statVideoFiles(String folderPath) async {
    final out = <String, FileSig>{};
    for (final path in await findVideoFiles(folderPath)) {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      out[path] = (
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    }
    return out;
  }
}

/// Filesystem-backed scanner using `dart:io`.
class FileSystemFolderScanner extends FolderScanner {
  const FileSystemFolderScanner();

  static const Set<String> videoExtensions = {
    '.mkv',
    '.mp4',
    '.avi',
    '.mov',
    '.m4v',
    '.webm',
    '.ts',
    '.wmv',
    '.flv',
    '.mpg',
    '.mpeg',
    '.m2ts',
  };

  @override
  Future<List<String>> findVideoFiles(String folderPath) async {
    final walk = await _walk(folderPath);
    _logSkipped(walk.skipped);
    return walk.files;
  }

  /// The walk AND the 8,000 stats on another isolate. The UI isolate used to
  /// do both, one `await` at a time, and on a network mount each stat is a
  /// round trip — a first scan of a large library was seconds of dropped
  /// frames before a single title was looked up. Nothing but strings and
  /// numbers crosses the boundary; the log lines for unreadable
  /// subdirectories come back as a list and are written from here, because
  /// `AppLog` is per-isolate.
  @override
  Future<Map<String, FileSig>> statVideoFiles(String folderPath) async {
    final result = await Isolate.run(() => _walkAndStat(folderPath));
    _logSkipped(result.skipped);
    return result.files;
  }

  static void _logSkipped(List<String> skipped) {
    for (final dir in skipped) {
      // One unreadable subdirectory must not abort the walk — but it must
      // not vanish silently either.
      AppLog.warn('Scan: skipped unreadable $dir');
    }
  }

  /// [findVideoFiles] without the logging: the files, and the directories
  /// that could not be listed. Runs on whichever isolate calls it.
  static Future<({List<String> files, List<String> skipped})> _walk(
    String folderPath,
  ) async {
    final root = Directory(folderPath);
    if (!await root.exists()) {
      throw FileSystemException('Library folder not found', folderPath);
    }

    // Manual depth-agnostic walk. We do NOT use `list(recursive: true)`: it
    // descends into hidden, permission-denied system dirs at a volume root
    // (.Spotlight-V100, .Trashes, .fseventsd) and one unreadable subdir aborts
    // the entire stream — so selecting a drive root found nothing.
    final files = <String>[];
    final pending = <Directory>[];
    final skipped = <String>[];

    // The root's listing errors propagate (an unreadable root is a real "lost
    // access" the sync surfaces loudly and preserves cached files for).
    _collect(
      await root.list(followLinks: false).toList(),
      files,
      pending,
      skipped,
    );

    // Descendant listings are tolerant: skip an unreadable subdir and keep
    // walking, rather than failing the whole scan.
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        skipped.add(dir.path);
        continue;
      }
      _collect(entries, files, pending, skipped);
    }

    files.sort();
    return (files: files, skipped: skipped);
  }

  static Future<({Map<String, FileSig> files, List<String> skipped})>
  _walkAndStat(String folderPath) async {
    final walk = await _walk(folderPath);
    final out = <String, FileSig>{};
    for (final path in walk.files) {
      final stat = await File(path).stat();
      // Listed a moment ago, gone now — a download finishing, a Finder move.
      // `stat()` does not throw for that; it reports notFound with size -1,
      // which would otherwise be cached as a real fingerprint.
      if (stat.type == FileSystemEntityType.notFound) continue;
      out[path] = (
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    }
    return (files: out, skipped: walk.skipped);
  }

  /// Add video files from [entries] to [files], and queue non-hidden
  /// subdirectories onto [pending]. Hidden entries (names starting with `.`)
  /// are skipped BEFORE descending — this is what excludes the volume-root
  /// system dirs without ever trying to read them.
  static void _collect(
    List<FileSystemEntity> entries,
    List<String> files,
    List<Directory> pending,
    List<String> skipped,
  ) {
    for (final entity in entries) {
      final name = basenameOf(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        pending.add(entity);
      } else if (entity is File) {
        if (_isVideoName(name)) files.add(entity.path);
      } else if (entity is Link) {
        // A symlink was neither a File nor a Directory to the walk, so it was
        // skipped without a word. A link TO a file is a file the player can
        // open (mpv follows it) — included under the link's own path, so the
        // library shows the name the user gave it. A link to a folder is not
        // followed (a cycle would never end) but is reported, not swallowed.
        final target = FileSystemEntity.typeSync(entity.path);
        if (target == FileSystemEntityType.file && _isVideoName(name)) {
          files.add(entity.path);
        } else if (target == FileSystemEntityType.directory) {
          skipped.add('${entity.path} (a link to a folder — not followed)');
        }
      }
    }
  }

  static bool _isVideoName(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 &&
        videoExtensions.contains(name.substring(dot).toLowerCase());
  }
}
