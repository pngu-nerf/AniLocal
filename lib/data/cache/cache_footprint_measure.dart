import 'dart:io';
import 'dart:isolate';

import '../../domain/models/cache_footprint.dart';
import 'cache_connection.dart';

/// Measure the data folder, OFF the UI isolate.
///
/// The four paths are resolved here, on the main isolate, because
/// `path_provider` is a plugin and plugins are not reachable from
/// `Isolate.run`; only the walk crosses over (plain `dart:io`, like the
/// scanner's `statVideoFiles`). A cover directory of a few thousand files is
/// a few thousand stats, which is exactly the work the UI isolate must not do.
Future<CacheFootprint> measureCacheFootprint() async {
  final dbPath = (await cacheDatabaseFile()).path;
  final artDir = (await coverArtDirectory()).path;
  final logsDir = (await logsDirectory()).path;
  final rootDir = (await dataDirectory()).path;
  return Isolate.run(
    () => measureFootprintSync(
      dbPath: dbPath,
      artDir: artDir,
      logsDir: logsDir,
      rootDir: rootDir,
    ),
  );
}

/// The testable half: pure over paths, synchronous, and never throws — a
/// file that vanishes mid-walk or cannot be stat'ed counts as nothing.
CacheFootprint measureFootprintSync({
  required String dbPath,
  required String artDir,
  required String logsDir,
  required String rootDir,
}) {
  final dbParts = {for (final s in kDatabaseSidecars) '$dbPath$s'};
  var database = 0;
  for (final part in dbParts) {
    database += _fileSize(part);
  }
  final art = _directorySize(artDir);
  final logs = _directorySize(logsDir);

  // Everything else directly under the data folder — the id map, quarantined
  // caches and covers — so the total is what the folder really takes.
  var other = 0;
  final root = Directory(rootDir);
  try {
    if (root.existsSync()) {
      for (final entry in root.listSync(followLinks: false)) {
        final path = entry.path;
        if (path == artDir || path == logsDir || dbParts.contains(path)) {
          continue;
        }
        other += entry is Directory ? _directorySize(path) : _fileSize(path);
      }
    }
  } on FileSystemException {
    // A root that cannot be listed: report what was measured so far.
  }
  return CacheFootprint(
    databaseBytes: database,
    artBytes: art,
    logsBytes: logs,
    otherBytes: other,
  );
}

int _fileSize(String path) {
  try {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  } on FileSystemException {
    return 0;
  }
}

int _directorySize(String path) {
  final dir = Directory(path);
  var total = 0;
  try {
    if (!dir.existsSync()) return 0;
    for (final entry in dir.listSync(recursive: true, followLinks: false)) {
      if (entry is File) total += _fileSize(entry.path);
    }
  } on FileSystemException {
    // Partial is better than nothing; the row says what it measured.
  }
  return total;
}
