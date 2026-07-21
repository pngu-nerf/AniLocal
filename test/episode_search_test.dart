import 'package:anilocal/ui/series_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('episodeMatchesQuery', () {
    test('a blank query matches everything', () {
      expect(episodeMatchesQuery(number: 47, query: ''), isTrue);
      expect(episodeMatchesQuery(number: 47, query: '   '), isTrue);
    });

    test('number match is PREFIX, not arbitrary substring', () {
      // Narrows as you type: "4" → 4, 40–49; "14" → 14, 140–149.
      expect(episodeMatchesQuery(number: 4, query: '4'), isTrue);
      expect(episodeMatchesQuery(number: 40, query: '4'), isTrue);
      expect(episodeMatchesQuery(number: 47, query: '4'), isTrue);
      expect(episodeMatchesQuery(number: 140, query: '14'), isTrue);
      expect(episodeMatchesQuery(number: 1, query: '1'), isTrue);
      expect(
        episodeMatchesQuery(number: 141, query: '1'),
        isTrue,
      ); // 141 has prefix 1
      // But NOT arbitrary substring: a prefix must anchor at the start.
      expect(episodeMatchesQuery(number: 47, query: '7'), isFalse);
      expect(episodeMatchesQuery(number: 41, query: '2'), isFalse);
      expect(
        episodeMatchesQuery(number: 141, query: '41'),
        isFalse,
      ); // not a prefix
      expect(episodeMatchesQuery(number: 5, query: '4'), isFalse);
    });

    test('filename is matched by case-insensitive substring', () {
      const file = 'Dragon Ball - 09 [480p][DUAL].mkv';
      // Text from the filename is searchable...
      expect(
        episodeMatchesQuery(number: 9, fileName: file, query: '480'),
        isTrue,
      );
      expect(
        episodeMatchesQuery(number: 9, fileName: file, query: 'dual'),
        isTrue,
      );
      // ...and the exact number still matches regardless of the filename.
      expect(
        episodeMatchesQuery(number: 9, fileName: file, query: '9'),
        isTrue,
      );
      expect(
        episodeMatchesQuery(number: 9, fileName: file, query: 'zzz'),
        isFalse,
      );
    });

    test('a missing/ghost episode (no file) matches by number only', () {
      expect(episodeMatchesQuery(number: 141, query: '141'), isTrue);
      expect(
        episodeMatchesQuery(number: 141, fileName: null, query: '480'),
        isFalse,
      );
    });
  });
}
