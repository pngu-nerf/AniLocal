import 'dart:io';

import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/diagnostics/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// `statVideoFiles` is the walk AND the stats on another isolate. It must
/// answer exactly what `findVideoFiles` + a stat per file answers inline —
/// same files, same fingerprints — and the unreadable-directory warnings must
/// still land in THIS isolate's log.
void main() {
  group('FolderScanner.statVideoFiles', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('anilocal_stat_');
      await Directory('${root.path}/Show A/.hidden').create(recursive: true);
      await File('${root.path}/Show A/A - 01.mkv').writeAsString('abc');
      await File('${root.path}/Show A/A - 02.mkv').writeAsString('abcdef');
      await File('${root.path}/Show A/.hidden/x.mkv').writeAsString('no');
      await File('${root.path}/notes.txt').writeAsString('skip me');
      await Directory('${root.path}/Show B').create();
      await File('${root.path}/Show B/B - 01.mp4').writeAsString('q');
    });
    tearDown(() async {
      await Process.run('chmod', ['-R', '755', root.path]);
      await root.delete(recursive: true);
    });

    test('matches the inline walk, file for file and byte for byte', () async {
      const scanner = FileSystemFolderScanner();
      final inline = <String, FileSig>{};
      for (final p in await scanner.findVideoFiles(root.path)) {
        final s = await File(p).stat();
        inline[p] = (
          size: s.size,
          modifiedMs: s.modified.millisecondsSinceEpoch,
        );
      }
      final isolated = await scanner.statVideoFiles(root.path);
      expect(isolated, inline);
      expect(isolated, hasLength(3), reason: 'hidden dir and .txt excluded');
      expect(isolated.values.map((s) => s.size).toSet(), {3, 6, 1});
    });

    test(
      'an unreadable subdirectory is skipped AND logged from here',
      () async {
        AppLog.reset();
        final locked = Directory('${root.path}/Locked')..createSync();
        await File('${locked.path}/L - 01.mkv').writeAsString('z');
        await Process.run('chmod', ['000', locked.path]);
        final found = await const FileSystemFolderScanner().statVideoFiles(
          root.path,
        );
        expect(found, hasLength(3));
        expect(
          AppLog.dump(),
          contains('Scan: skipped unreadable ${locked.path}'),
          reason:
              'the isolate returns the skipped paths; the log is written here',
        );
      },
    );

    test('a missing root throws, like findVideoFiles', () async {
      expect(
        () =>
            const FileSystemFolderScanner().statVideoFiles('${root.path}/nope'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
