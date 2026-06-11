import 'package:anilocal/ui/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seriesUnavailable (grey-out rule)', () {
    test('all source folders missing -> unavailable', () {
      expect(
        seriesUnavailable({'/Volumes/USB/Anime'}, {'/Volumes/USB/Anime'}),
        isTrue,
      );
    });

    test('a connected folder keeps it available', () {
      // Single source on a connected folder.
      expect(
        seriesUnavailable({'/Users/me/Anime'}, {'/Volumes/USB/Anime'}),
        isFalse,
      );
    });

    test('multi-source: one connected source -> NOT unavailable', () {
      // Sources span a missing drive and a connected folder -> still playable.
      expect(
        seriesUnavailable(
          {'/Volumes/USB/Anime', '/Users/me/Anime'},
          {'/Volumes/USB/Anime'},
        ),
        isFalse,
      );
    });

    test('multi-source: ALL sources missing -> unavailable', () {
      expect(
        seriesUnavailable(
          {'/Volumes/USB/Anime', '/Volumes/NAS/Anime'},
          {'/Volumes/USB/Anime', '/Volumes/NAS/Anime'},
        ),
        isTrue,
      );
    });

    test('no sources -> not unavailable (nothing to grey)', () {
      expect(seriesUnavailable(const {}, {'/Volumes/USB/Anime'}), isFalse);
    });

    test('nothing missing -> not unavailable', () {
      expect(seriesUnavailable({'/Volumes/USB/Anime'}, const {}), isFalse);
    });
  });
}
