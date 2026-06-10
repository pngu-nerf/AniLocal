import 'dart:io';

/// Walks a library folder and finds video files. Behind an interface so the
/// traversal strategy is swappable and testable.
abstract interface class FolderScanner {
  /// Return absolute paths of video files under [folderPath] (recursive),
  /// sorted for stable ordering. Throws if the folder does not exist.
  Future<List<String>> findVideoFiles(String folderPath);
}

/// Filesystem-backed scanner using `dart:io`.
class FileSystemFolderScanner implements FolderScanner {
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

    // The root's listing errors propagate (an unreadable root is a real "lost
    // access" the sync surfaces loudly and preserves cached files for).
    _collect(await root.list(followLinks: false).toList(), files, pending);

    // Descendant listings are tolerant: skip an unreadable subdir and keep
    // walking, rather than failing the whole scan.
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      _collect(entries, files, pending);
    }

    files.sort();
    return files;
  }

  /// Add video files from [entries] to [files], and queue non-hidden
  /// subdirectories onto [pending]. Hidden entries (names starting with `.`)
  /// are skipped BEFORE descending — this is what excludes the volume-root
  /// system dirs without ever trying to read them.
  void _collect(
    List<FileSystemEntity> entries,
    List<String> files,
    List<Directory> pending,
  ) {
    for (final entity in entries) {
      final name = _basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        pending.add(entity);
      } else if (entity is File) {
        final dot = name.lastIndexOf('.');
        if (dot < 0) continue;
        if (videoExtensions.contains(name.substring(dot).toLowerCase())) {
          files.add(entity.path);
        }
      }
    }
  }

  String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }
}
