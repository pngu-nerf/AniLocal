import 'dart:io';

import 'package:anilocal/data/folders/folder_access.dart';
import 'package:anilocal/data/folders/tcc_folder_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const home = '/Users/test';

  ({String root, String label})? cat(String path) =>
      tccCategoryRoot(path, home);

  test('maps the three home TCC categories to their roots', () {
    expect(cat('$home/Downloads/Anime')?.root, '$home/Downloads');
    expect(cat('$home/Downloads/Anime')?.label, 'Downloads');
    expect(cat('$home/Documents/Shows/x.mkv')?.root, '$home/Documents');
    expect(cat('$home/Desktop')?.root, '$home/Desktop'); // the root itself
  });

  test('maps a removable volume to its volume root (separate category)', () {
    final c = cat('/Volumes/Backup HDD/Anime/Show - 01.mkv');
    expect(c?.root, '/Volumes/Backup HDD');
    expect(c?.label, contains('Backup HDD'));
  });

  test('non-protected locations have no category (no prompt)', () {
    expect(cat('$home/Movies/Anime'), isNull);
    expect(cat('$home/anilocal-test/library'), isNull);
    expect(cat('/opt/media'), isNull);
  });

  test('does not match a sibling whose name merely starts the same', () {
    // ~/DownloadsX must NOT be treated as under ~/Downloads.
    expect(cat('$home/DownloadsArchive/x'), isNull);
  });

  group('FolderAccessResult expresses three states', () {
    test('accessible / missing / denied are distinct', () {
      expect(
        const FolderAccessResult.granted('x').state,
        FolderAccessState.accessible,
      );
      expect(
        const FolderAccessResult.notApplicable().state,
        FolderAccessState.accessible,
      );
      const missing = FolderAccessResult.missing('the volume “USB”');
      expect(missing.isMissing, isTrue);
      expect(missing.isDenied, isFalse);
      const denied = FolderAccessResult.denied('Downloads');
      expect(denied.isDenied, isTrue);
      expect(denied.isMissing, isFalse);
    });
  });

  group('ensureAccess: missing mount vs permission denial', () {
    late Directory tmp;
    late TccFolderAccess access;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('anilocal_access_');
      access = TccFolderAccess(home: tmp.path);
    });
    tearDown(() async => tmp.delete(recursive: true));

    test(
      'unplugged drive (/Volumes mount absent) -> missing, NOT denied',
      () async {
        final r = await access.ensureAccess(
          '/Volumes/NoSuchAniLocalDrive_2f9c/Anime',
        );
        expect(r.state, FolderAccessState.missing);
        expect(r.categoryLabel, contains('NoSuchAniLocalDrive_2f9c'));
      },
    );

    test('category root that does not exist -> missing', () async {
      final r = await access.ensureAccess('${tmp.path}/Desktop/Anime');
      expect(r.state, FolderAccessState.missing);
    });

    test('readable category root -> accessible', () async {
      await Directory('${tmp.path}/Downloads').create();
      final r = await access.ensureAccess('${tmp.path}/Downloads/Anime');
      expect(r.state, FolderAccessState.accessible);
    });

    test('not under a category/volume -> accessible (no prompt)', () async {
      final r = await access.ensureAccess('${tmp.path}/random/Anime');
      expect(r.state, FolderAccessState.accessible);
      expect(r.categoryLabel, isNull);
    });

    test('exists but read blocked -> denied', () async {
      final docs = await Directory('${tmp.path}/Documents').create();
      await Process.run('chmod', ['000', docs.path]);
      addTearDown(() => Process.run('chmod', ['755', docs.path]));
      // Only meaningful if the chmod actually blocks reads here (not as root).
      var blocked = false;
      try {
        docs.listSync();
      } on FileSystemException {
        blocked = true;
      }
      if (!blocked) return;

      final r = await access.ensureAccess('${docs.path}/Anime');
      expect(r.state, FolderAccessState.denied);
    });
  });
}
