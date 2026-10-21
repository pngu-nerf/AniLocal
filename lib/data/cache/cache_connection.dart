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

/// The database file and the sidecars SQLite keeps beside it. One list, read
/// by the quarantine (which moves them together) and the size measurement
/// (which counts them together).
const List<String> kDatabaseSidecars = ['', '-wal', '-shm', '-journal'];

/// Set the cache aside, so the next launch starts empty — because it could
/// not be opened, or because the user chose to start over.
///
/// MOVED, never deleted: the file is renamed to `cache.sqlite.broken-<stamp>`
/// beside the original (its WAL and shm sidecars with it), so whatever it
/// held — watch state, fix-matches — can still be recovered by hand or sent
/// with a report. The cover directory goes with it, under the SAME stamp, and
/// that is load-bearing: covers are named by series id and reused when the
/// cached URL is unknown, and a fresh cache mints ids from the start again, so
/// a cover left behind would be shown for a DIFFERENT show. Returns the
/// quarantined database path. The caller closes the database first; the app
/// then quits, because a Drift database cannot be reopened in place and every
/// repository holds the closed one.
Future<String> quarantineCacheDatabase() async => quarantineCacheFile(
  await cacheDatabaseFile(),
  art: await coverArtDirectory(),
);

/// [quarantineCacheDatabase] for a given file (and cover directory) — the
/// testable half.
Future<String> quarantineCacheFile(File file, {Directory? art}) async {
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final target = '${file.path}.broken-$stamp';
  for (final suffix in kDatabaseSidecars) {
    final part = File('${file.path}$suffix');
    if (await part.exists()) await part.rename('$target$suffix');
  }
  if (art != null && await art.exists()) {
    await art.rename('${art.path}.broken-$stamp');
  }
  return target;
}

/// The app's data folder — everything it keeps lives under here: the cache
/// database, `art/`, `logs/`, and the cross-database id map directly inside.
/// Named to the user by Settings › Maintenance.
Future<Directory> dataDirectory() async {
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
