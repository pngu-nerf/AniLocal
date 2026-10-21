import 'dart:io';

import 'package:anilocal/data/cache/cache_footprint_measure.dart';
import 'package:anilocal/domain/models/cache_footprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// The size Settings › Maintenance shows. What matters: every part of the data
/// folder is counted exactly once, a missing part counts as nothing rather
/// than failing, and the words match Finder's decimal units.
void main() {
  group('measureFootprintSync', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('footprint'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String relative, int bytes) {
      final file = File('${dir.path}/$relative')..createSync(recursive: true);
      file.writeAsBytesSync(List.filled(bytes, 0));
    }

    test('counts the database with its sidecars, art, logs and the rest', () {
      write('cache.sqlite', 1000);
      write('cache.sqlite-wal', 200);
      write('art/1.jpg', 300);
      write('art/2.png', 400);
      write('logs/app.log', 50);
      write('crossmap.json', 60);
      write('cache.sqlite.broken-2026/x', 7); // a set-aside cache: "other"

      final f = measureFootprintSync(
        dbPath: '${dir.path}/cache.sqlite',
        artDir: '${dir.path}/art',
        logsDir: '${dir.path}/logs',
        rootDir: dir.path,
      );

      expect(f.databaseBytes, 1200);
      expect(f.artBytes, 700);
      expect(f.logsBytes, 50);
      expect(f.otherBytes, 67, reason: 'the id map and the quarantined cache');
      expect(f.totalBytes, 2017);
    });

    test('a part that does not exist is zero, not an error', () {
      final f = measureFootprintSync(
        dbPath: '${dir.path}/cache.sqlite',
        artDir: '${dir.path}/art',
        logsDir: '${dir.path}/logs',
        rootDir: '${dir.path}/nowhere',
      );
      expect(
        f,
        const CacheFootprint(
          databaseBytes: 0,
          artBytes: 0,
          logsBytes: 0,
          otherBytes: 0,
        ),
      );
    });
  });

  test('formatBytes: decimal units, three significant figures', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1.00 kB');
    expect(formatBytes(48200000), '48.2 MB');
    expect(formatBytes(123456789), '123 MB');
    expect(formatBytes(1020000000), '1.02 GB');
    expect(formatBytes(5 * 1000 * 1000 * 1000 * 1000), '5.00 TB');
  });
}
