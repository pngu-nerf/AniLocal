import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// Open the on-disk cache database under the app support directory. Tests
/// inject `NativeDatabase.memory()` instead, so this file holds the only
/// filesystem/path_provider coupling.
LazyDatabase openCacheDatabase() {
  return LazyDatabase(
    () async => NativeDatabase.createInBackground(await cacheDatabaseFile()),
  );
}

/// Where the cache lives — the one path, so the library's load-error panel
/// can NAME the file it could not open and the reset knows what to move.
Future<File> cacheDatabaseFile() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/anilocal');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}/cache.sqlite');
}

/// Set a cache that cannot be opened aside, so the next launch starts empty.
///
/// MOVED, never deleted: the file is renamed to `cache.sqlite.broken-<stamp>`
/// beside the original (its WAL and shm sidecars with it), so whatever it
/// held — watch state, fix-matches — can still be recovered by hand or sent
/// with a report. Returns the quarantined path. The caller closes the
/// database first; the app then quits, because a Drift database cannot be
/// reopened in place and every repository holds the closed one.
Future<String> quarantineCacheDatabase() async =>
    quarantineCacheFile(await cacheDatabaseFile());

/// [quarantineCacheDatabase] for a given file — the testable half.
Future<String> quarantineCacheFile(File file) async {
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final target = '${file.path}.broken-$stamp';
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final part = File('${file.path}$suffix');
    if (await part.exists()) await part.rename('$target$suffix');
  }
  return target;
}

/// Directory holding derived data caches that aren't the DB — currently the
/// cross-database id map. Separate from art so clearing one can't affect the
/// other.
Future<Directory> derivedDataDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/anilocal');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Directory where downloaded cover art is stored.
Future<Directory> coverArtDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/anilocal/art');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Directory for the app log (`app.log` + one rotated backup). Beside the
/// cache, so "clear app data" is one folder and "open log folder" is one path.
Future<Directory> logsDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/anilocal/logs');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
