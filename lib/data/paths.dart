/// The last path segment, for either separator. ONE implementation: the
/// scanner and the fill path each carried their own identical copy.
String basenameOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i == -1 ? path : path.substring(i + 1);
}
