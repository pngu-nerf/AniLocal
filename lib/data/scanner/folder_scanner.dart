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
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw FileSystemException('Library folder not found', folderPath);
    }

    final files = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('.')) continue; // skip hidden / macOS junk
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = name.substring(dot).toLowerCase();
      if (videoExtensions.contains(ext)) {
        files.add(entity.path);
      }
    }
    files.sort();
    return files;
  }
}
