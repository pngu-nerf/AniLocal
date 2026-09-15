import 'metadata_failure.dart';
import 'user_facing_failure.dart';

/// Adding a library folder was refused, with the sentence to show. The
/// picker returned a folder the library cannot take as another entry: one it
/// already has, or one that nests with one it has — a nested pair walks the
/// same files twice and presents them as duplicate copies.
class FolderRefused implements Exception, UserFacingFailure {
  const FolderRefused(this.userMessage);

  @override
  final String userMessage;

  @override
  MetadataFailure? get failure => null;

  @override
  String toString() => 'FolderRefused: $userMessage';
}

/// A folder path as the library stores it: no trailing slash. The picker
/// returns `/Volumes/Anime/` for a volume root and `/Volumes/Anime/Shows`
/// for a folder in it, and `file_cache` is keyed by the stored string, so
/// the same folder written both ways used to be two folders.
String normalizeFolderPath(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Why [candidate] cannot join [existing], or null when it can. Pure, so the
/// rule is tested without a picker or a database.
///
/// Re-adding a folder used to be accepted and silently demoted it to last
/// priority (the insert was an upsert that rewrote `sort_order`); a parent
/// or child of an existing folder was accepted and every file under the
/// overlap became two copies.
FolderRefused? folderRefusal(String candidate, Iterable<String> existing) {
  final path = normalizeFolderPath(candidate);
  for (final raw in existing) {
    final other = normalizeFolderPath(raw);
    if (other == path) {
      return FolderRefused('$path is already in your library.');
    }
    if (path.startsWith('$other/')) {
      return FolderRefused(
        '$path is inside $other, which is already in your library — its '
        'files are already scanned.',
      );
    }
    if (other.startsWith('$path/')) {
      return FolderRefused(
        '$path contains $other, which is already in your library. Remove '
        'that folder first if you want the whole of $path.',
      );
    }
  }
  return null;
}
