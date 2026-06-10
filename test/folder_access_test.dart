import 'package:anilocal/data/folders/folder_access.dart';
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
}
