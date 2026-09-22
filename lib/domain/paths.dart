import 'dart:io' show Platform;

/// The last path segment, for either separator. ONE implementation: the
/// scanner and the fill path each carried their own identical copy.
String basenameOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i == -1 ? path : path.substring(i + 1);
}

/// Whether [path] IS [folder] or lies under it, for either separator, with
/// [folder]'s trailing separators ignored. Case-insensitive on Windows by
/// default (its volumes are), exact elsewhere; [caseInsensitive] overrides for
/// tests. `startsWith('$folder/')` was the rule before, which no Windows path
/// ever satisfied.
bool isUnderPath(String path, String folder, {bool? caseInsensitive}) {
  // Compare with one separator so `C:/Anime` and `C:\Anime` are the same
  // folder; the replacement is one-to-one, so lengths still index [path].
  var f = folder.replaceAll('\\', '/');
  while (f.length > 1 && f.endsWith('/')) {
    f = f.substring(0, f.length - 1);
  }
  var p = path.replaceAll('\\', '/');
  if (caseInsensitive ?? Platform.isWindows) {
    p = p.toLowerCase();
    f = f.toLowerCase();
  }
  if (p == f) return true;
  return p.length > f.length && p.startsWith('$f/');
}

/// [path] split at its last separator (either kind): the parent and the last
/// segment. No separator, or only a leading one → parent `''`, name = [path].
({String parent, String name}) splitLast(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  if (i <= 0) return (parent: '', name: path);
  return (parent: path.substring(0, i), name: path.substring(i + 1));
}
