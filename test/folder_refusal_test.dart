import 'package:anilocal/domain/models/folder_refused.dart';
import 'package:flutter_test/flutter_test.dart';

/// The nesting rule, on Windows shapes: either separator, either case. The
/// posix cases live in interruptions_test.
void main() {
  test('a nested Windows folder is refused, both directions', () {
    expect(folderRefusal(r'C:\Anime\Show', [r'C:\Anime']), isNotNull);
    expect(folderRefusal(r'C:\Anime', [r'C:\Anime\Show']), isNotNull);
    expect(folderRefusal('C:/Anime/Show', [r'C:\Anime']), isNotNull);
    expect(folderRefusal(r'D:\Anime', [r'C:\Anime']), isNull);
  });

  test('one folder, three spellings', () {
    expect(
      folderRefusal('C:/Anime/', [r'C:\Anime'])?.userMessage,
      contains('already in your library'),
    );
    expect(
      folderRefusal(r'c:\anime\', [
        r'C:\Anime',
      ], caseInsensitive: true)?.userMessage,
      contains('already in your library'),
    );
    expect(
      folderRefusal('C:/Anime', [
        r'C:\Anime',
      ], caseInsensitive: false)?.userMessage,
      contains('already in your library'),
    );
  });

  test('a root folder contains everything on the drive', () {
    expect(
      folderRefusal(r'C:\', [r'C:\Anime'])?.userMessage,
      contains('contains'),
    );
    expect(
      folderRefusal('/Volumes/Anime/Shows', ['/'])?.userMessage,
      contains('inside'),
    );
  });
}
