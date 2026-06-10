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

/// Directory where downloaded cover art is stored.
Future<Directory> coverArtDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/anilocal/art');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
