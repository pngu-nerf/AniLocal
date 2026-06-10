import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('Media resolves a messy fansub path (spaces + [brackets]) unmangled', () {
    // The exact shape PlaybackController feeds media_kit: a real release name.
    const path =
        '/Users/x/Anime/[SubsPlease] Show Name - 01 [1080p][A1B2C3D4].mkv';

    final resolved = Media(path).uri;

    // Plain path passes through to libmpv intact — no broken percent-encoding,
    // no truncation at the first space/bracket (which a `file://` string would
    // have produced).
    expect(resolved, path);
  });

  test('handles spaces in directory components too', () {
    const path =
        '/Volumes/Backup HDD/Anime/Yowayowa Sensei/'
        '[WF] Yowayowa Sensei - 09 [ADN WEB-DL 1080p AVC AAC] [679D0F19].mkv';
    expect(Media(path).uri, path);
  });
}
