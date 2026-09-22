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

  test('splitLast handles either separator and a bare name', () {
    expect(splitLast('/a/b/c.mkv'), (parent: '/a/b', name: 'c.mkv'));
    expect(splitLast(r'C:\a\c.mkv'), (parent: r'C:\a', name: 'c.mkv'));
    expect(splitLast('c.mkv'), (parent: '', name: 'c.mkv'));
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
    test('volumeSubpathOf under a drive root, and null off it', () {
      expect(volumeSubpathOf(r'D:\Anime\shows', r'D:\Anime'), 'shows');
      expect(volumeSubpathOf(r'D:\Anime', r'D:\Anime'), '');
      expect(volumeSubpathOf(r'E:\Anime', r'D:\Anime'), isNull);
    });
  });
}
