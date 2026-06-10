import 'dart:io';

import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scanner = FileSystemFolderScanner();
  late Directory root;
  final toRestore = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scan_test_');
  });

  tearDown(() async {
    for (final p in toRestore) {
      await Process.run('chmod', ['755', p]);
    }
    toRestore.clear();
    await root.delete(recursive: true);
  });

  Future<void> writeFile(String relative) async {
    final f = File('${root.path}/$relative');
    await f.parent.create(recursive: true);
    await f.writeAsString('x');
  }

  List<String> names(List<String> paths) =>
      paths.map((p) => p.split(Platform.pathSeparator).last).toList();

  test('finds videos at ANY depth under the selected root', () async {
    await writeFile('Movie - 01.mkv'); // at root
    await writeFile('Show A/Show A - 01.mkv'); // depth 1
    await writeFile('Show B/Season 2/Show B - 05.mkv'); // depth 2
    await writeFile('Show C/extras/notes.txt'); // non-video, ignored

    final files = await scanner.findVideoFiles(root.path);

    expect(names(files), [
      'Movie - 01.mkv',
      'Show A - 01.mkv',
      'Show B - 05.mkv',
    ]);
  });

  test(
    'skips hidden system dirs without descending (the volume-root case)',
    () async {
      await writeFile('Show - 01.mkv');
      await writeFile('.Spotlight-V100/Store-V2/junk.mkv'); // must be ignored
      await writeFile('.Trashes/old.mkv'); // must be ignored

      final files = await scanner.findVideoFiles(root.path);

      expect(names(files), ['Show - 01.mkv']);
    },
  );

  test(
    'skips a permission-denied subdir instead of aborting the walk',
    () async {
      await writeFile('Good - 01.mkv');
      await writeFile('locked/inside.mkv');
      final locked = '${root.path}/locked';
      await Process.run('chmod', ['000', locked]);
      toRestore.add(locked); // so tearDown can delete it

      final files = await scanner.findVideoFiles(root.path);

      expect(names(files), ['Good - 01.mkv']);
    },
  );

  test(
    'an unreadable / missing ROOT still throws (loud, not silent)',
    () async {
      expect(
        () => scanner.findVideoFiles('${root.path}/does-not-exist'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
