import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/ui/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Series _series({
  String? english,
  String? romaji,
  String? native,
  bool pending = false,
}) => Series(
  anilistId: pending ? -42 : 1,
  titles: Titles(english: english, romaji: romaji, native: native),
  pending: pending,
);

void main() {
  group('seriesMatchesQuery (live library filter)', () {
    final s = _series(
      english: 'Frieren: Beyond Journey\'s End',
      romaji: 'Sousou no Frieren',
      native: '葬送のフリーレン',
    );

    test('blank query matches everything (clearing restores the library)', () {
      expect(seriesMatchesQuery(s, ''), isTrue);
      expect(seriesMatchesQuery(s, '   '), isTrue);
    });

    test('matches English title, case-insensitively', () {
      expect(seriesMatchesQuery(s, 'frieren'), isTrue);
      expect(seriesMatchesQuery(s, 'JOURNEY'), isTrue);
    });

    test('matches romaji title (a different name for the same show)', () {
      expect(seriesMatchesQuery(s, 'sousou'), isTrue);
    });

    test('matches native title', () {
      expect(seriesMatchesQuery(s, 'フリーレン'), isTrue);
    });

    test('substring anywhere matches, not just a prefix', () {
      expect(seriesMatchesQuery(s, 'beyond'), isTrue);
    });

    test('surrounding whitespace is ignored', () {
      expect(seriesMatchesQuery(s, '  frieren  '), isTrue);
    });

    test('a non-matching query is excluded', () {
      expect(seriesMatchesQuery(s, 'naruto'), isFalse);
    });

    test(
      'a pending placeholder is searchable by its parsed title (romaji)',
      () {
        final p = _series(romaji: '[SubsPlease] Dandadan - 01', pending: true);
        expect(seriesMatchesQuery(p, 'dandadan'), isTrue);
        expect(seriesMatchesQuery(p, 'bleach'), isFalse);
      },
    );
  });
}
