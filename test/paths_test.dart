import 'package:anilocal/data/folders/volume_resolver.dart';
import 'package:anilocal/domain/paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Path logic that ran off the macOS-only code path — the migration backfill
/// and the fix-match reverse lookup — but only ever met `/`-separated,
/// case-sensitive paths. A Windows library is `C:\…` and case-insensitive.
void main() {
  group('isUnderPath', () {
    test(
      'posix: the folder itself, a child, and not a sibling with a prefix',
      () {
        expect(isUnderPath('/a/b', '/a/b'), isTrue);
        expect(isUnderPath('/a/b/c.mkv', '/a/b'), isTrue);
        expect(
          isUnderPath('/a/bc/c.mkv', '/a/b'),
          isFalse,
          reason: 'prefix ≠ parent',
        );
        expect(
          isUnderPath('/a/b/c.mkv', '/a/b/'),
          isTrue,
          reason: 'trailing slash',
        );
      },
    );
    test(
      "the path's own trailing separator is ignored; an empty folder is nobody's parent",
      () {
        expect(isUnderPath('/Volumes/Anime/', '/Volumes/Anime'), isTrue);
        expect(isUnderPath('/a', ''), isFalse);
        expect(volumeSubpathOf('/Volumes/Anime/', '/Volumes/Anime'), '');
      },
    );
    test('a root is a parent of everything on it', () {
      expect(isUnderPath('/a', '/'), isTrue);
      expect(isUnderPath('/', '/'), isTrue);
      expect(isUnderPath(r'C:\a', r'C:\'), isTrue);
      expect(isUnderPath(r'C:\a', 'C:/'), isTrue);
      expect(isUnderPath(r'D:\a', r'C:\'), isFalse);
    });
    test('windows and mixed separators', () {
      expect(isUnderPath(r'C:\Anime\Show\ep.mkv', r'C:\Anime'), isTrue);
      expect(isUnderPath(r'C:\Anime\Show\ep.mkv', 'C:/Anime'), isTrue);
      expect(isUnderPath(r'C:\Animex\ep.mkv', r'C:\Anime'), isFalse);
    });
    test('case folds only when asked (Windows volumes)', () {
      expect(
        isUnderPath(r'c:\anime\ep.mkv', r'C:\Anime', caseInsensitive: true),
        isTrue,
      );
      expect(
        isUnderPath('/Anime/ep.mkv', '/anime', caseInsensitive: false),
        isFalse,
      );
    });
  });

  test(
    'splitLast handles either separator, a bare name, and a root parent',
    () {
      expect(splitLast('/a/b/c.mkv'), (parent: '/a/b', name: 'c.mkv'));
      expect(splitLast(r'C:\a\c.mkv'), (parent: r'C:\a', name: 'c.mkv'));
      expect(splitLast('c.mkv'), (parent: '', name: 'c.mkv'));
      // A bare root or drive keeps its separator: `C:` alone is drive-relative.
      expect(splitLast('/a'), (parent: '/', name: 'a'));
      expect(splitLast(r'C:\a'), (parent: r'C:\', name: 'a'));
      expect(splitLast('/a').name, basenameOf('/a'), reason: 'one basename');
    },
  );

  test(
    'normalizeFolderPath strips either trailing separator, keeps a root',
    () {
      expect(normalizeFolderPath('/a/b///'), '/a/b');
      expect(normalizeFolderPath(r'C:\Anime\'), r'C:\Anime');
      expect(normalizeFolderPath('/'), '/');
      expect(normalizeFolderPath(r'C:\'), r'C:\');
    },
  );

  test('relativeTo measures the normalised folder', () {
    expect(relativeTo('/a/b/c.mkv', '/a/b/'), 'c.mkv');
    expect(relativeTo('/a/b/c.mkv', '/a/b'), 'c.mkv');
    expect(relativeTo('/a/b', '/a/b/'), '');
    expect(relativeTo('/a', '/'), 'a');
    expect(relativeTo(r'C:\a\b', r'C:\'), r'a\b');
  });

  group('the volume helpers on Windows paths', () {
    test('rebaseToFolderRelative picks the folder and the relative part', () {
      expect(rebaseToFolderRelative(r'C:\Anime\Show\ep.mkv', [r'C:\Anime']), (
        folderPath: r'C:\Anime',
        relativePath: r'Show\ep.mkv',
      ));
      expect(rebaseToFolderRelative(r'D:\loose\ep.mkv', [r'C:\Anime']), (
        folderPath: r'D:\loose',
        relativePath: 'ep.mkv',
      ), reason: 'no folder matches: parent + name, not the whole path');
    });
    test(
      'a folder or mount given with a trailing separator loses no character',
      () {
        expect(rebaseToFolderRelative('/a/b/c.mkv', ['/a/b/']), (
          folderPath: '/a/b/',
          relativePath: 'c.mkv',
        ));
        expect(rebaseToFolderRelative(r'C:\a\b', [r'C:\']), (
          folderPath: r'C:\',
          relativePath: r'a\b',
        ));
        expect(
          volumeSubpathOf('/Volumes/Anime/shows', '/Volumes/Anime/'),
          'shows',
        );
        expect(rebaseToFolderRelative('/x', const []), (
          folderPath: '/',
          relativePath: 'x',
        ), reason: 'no folder matches a root file: root + name');
      },
    );
    test('the longest match is judged normalised, not by slash count', () {
      expect(
        rebaseToFolderRelative('/a/b/c/d.mkv', [
          '/a/b///',
          '/a/b/c',
        ]).folderPath,
        '/a/b/c',
      );
    });
    test('volumeSubpathOf under a drive root, and null off it', () {
      expect(volumeSubpathOf(r'D:\Anime\shows', r'D:\Anime'), 'shows');
      expect(volumeSubpathOf(r'D:\Anime', r'D:\Anime'), '');
      expect(volumeSubpathOf(r'E:\Anime', r'D:\Anime'), isNull);
    });
  });
}
