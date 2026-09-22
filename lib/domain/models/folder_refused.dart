import '../paths.dart';
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

/// Why [candidate] cannot join [existing], or null when it can. Pure, so the
/// rule is tested without a picker or a database.
///
/// Re-adding a folder used to be accepted and silently demoted it to last
/// priority (the insert was an upsert that rewrote `sort_order`); a parent
/// or child of an existing folder was accepted and every file under the
/// overlap became two copies.
FolderRefused? folderRefusal(
  String candidate,
  Iterable<String> existing, {
  bool? caseInsensitive,
}) {
  final path = normalizeFolderPath(candidate);
  for (final raw in existing) {
    final other = normalizeFolderPath(raw);
    // Either separator, and on Windows either case: `C:\Anime`, `C:/Anime`
    // and `c:\anime` are one folder, and `C:\Anime\Show` nests in it.
    final inside = isUnderPath(path, other, caseInsensitive: caseInsensitive);
    final contains = isUnderPath(other, path, caseInsensitive: caseInsensitive);
    if (inside && contains) {
      return FolderRefused('$path is already in your library.');
    }
    if (inside) {
      return FolderRefused(
        '$path is inside $other, which is already in your library — its '
        'files are already scanned.',
      );
    }
    if (contains) {
      return FolderRefused(
        '$path contains $other, which is already in your library. Remove '
        'that folder first if you want the whole of $path.',
      );
    }
  }
  return null;
}
