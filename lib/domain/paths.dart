import 'dart:io' show Platform;

/// The last path segment, for either separator. ONE implementation: the
/// scanner and the fill path each carried their own identical copy.
String basenameOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i == -1 ? path : path.substring(i + 1);
}

/// A folder path as the library stores it: no trailing separator, of either
/// kind. The picker returns `/Volumes/Anime/` for a volume root and
/// `/Volumes/Anime/Shows` for a folder in it, and `file_cache` is keyed by the
/// stored string, so the same folder written both ways used to be two folders.
/// A bare root keeps its one separator (`/`, `C:\`) — without it `C:` is a
/// drive-relative path, not the drive.
String normalizeFolderPath(String path) {
  var p = path;
  while (p.length > 1 && (p.endsWith('/') || p.endsWith('\\'))) {
    final head = p.substring(0, p.length - 1);
    if (head.isEmpty || head.endsWith(':')) break;
    p = head;
  }
  return p;
}

/// Whether [path] IS [folder] or lies under it, for either separator, with
/// [folder]'s trailing separators ignored and a root (`/`, `C:\`) a parent of
/// everything on it. Case-insensitive on Windows by default (its volumes
/// are), exact elsewhere; [caseInsensitive] overrides for tests.
/// `startsWith('$folder/')` was the rule before, which no Windows path ever
/// satisfied and no root ever did either (`'/a'.startsWith('//')`).
bool isUnderPath(String path, String folder, {bool? caseInsensitive}) {
  // One separator for the comparison; the replacement is one-to-one, so
  // lengths still index [path].
  var f = normalizeFolderPath(folder).replaceAll('\\', '/');
  if (f.isEmpty) return false; // nothing is "under" no folder
  // The path's own trailing separator is ignored too: a folder row stored
  // before normalisation existed (`/Volumes/Anime/`) must still match its
  // mount. `relativeTo` measures the folder, not the path, so slicing is
  // unaffected.
  var p = normalizeFolderPath(path).replaceAll('\\', '/');
  if (caseInsensitive ?? Platform.isWindows) {
    p = p.toLowerCase();
    f = f.toLowerCase();
  }
  if (p == f) return true;
  final prefix = f.endsWith('/') ? f : '$f/';
  return p.length > prefix.length && p.startsWith(prefix);
}

/// The part of [path] below [folder], without its leading separator — `''`
/// for the folder itself. Only meaningful when [isUnderPath] holds. Measures
/// the NORMALISED folder, so a folder given with a trailing separator does
/// not eat the first character of the remainder.
String relativeTo(String path, String folder) {
  final f = normalizeFolderPath(folder);
  if (path.length <= f.length) return '';
  final cut = f.endsWith('/') || f.endsWith('\\') ? f.length : f.length + 1;
  return path.substring(cut);
}

/// [path] split at its last separator (either kind): the parent and the last
/// segment. A parent that would be a bare root or drive keeps its separator
/// (`/a` → `/` + `a`, `C:\a` → `C:\` + `a`); no separator → parent `''`.
({String parent, String name}) splitLast(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  if (i == -1) return (parent: '', name: path);
  final head = path.substring(0, i);
  final parent = head.isEmpty || head.endsWith(':')
      ? path.substring(0, i + 1)
      : head;
  return (parent: parent, name: path.substring(i + 1));
}
