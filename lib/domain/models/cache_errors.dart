/// The library cache on disk was written by a NEWER build than this one.
///
/// A domain type, not a data one, because the UI has to recognise it: this is
/// the one open-failure that has a specific remedy ("update the app") rather
/// than a generic one. The data layer throws it before any migration statement
/// runs, so the version label on disk stays honest — drift would otherwise
/// treat a downgrade as an upgrade and re-stamp the version downward after
/// running nothing, and the next real upgrade would then fail.
class CacheNewerThanAppException implements Exception {
  const CacheNewerThanAppException(this.onDisk, this.supported);

  final int onDisk;
  final int supported;

  @override
  String toString() =>
      'CacheNewerThanAppException: cache is schema v$onDisk, this build '
      'supports up to v$supported';
}
