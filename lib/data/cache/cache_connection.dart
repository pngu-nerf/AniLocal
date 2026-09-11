import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// Open the on-disk cache database under the app support directory. Tests
/// inject `NativeDatabase.memory()` instead, so this file holds the only
/// filesystem/path_provider coupling.
LazyDatabase openCacheDatabase() {
  return LazyDatabase(() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/anilocal');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return NativeDatabase.createInBackground(File('${dir.path}/cache.sqlite'));
  });
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
