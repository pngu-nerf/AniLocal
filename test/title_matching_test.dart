import 'package:anilocal/data/scanner/title_matching.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:flutter_test/flutter_test.dart';

Series _series(int id, {String? romaji, String? english}) => Series(
  anilistId: id,
  titles: Titles(romaji: romaji, english: english),
);

void main() {
  group('normalizeTitle', () {
    test('lowercases, strips punctuation, collapses whitespace', () {
      expect(normalizeTitle('Sousou no Frieren!'), 'sousou no frieren');
      expect(normalizeTitle('Re:ZERO  -Starting-'), 're zero starting');
    });
  });

  group('titleSimilarity', () {
    test('identical normalized titles score 1.0', () {
      expect(titleSimilarity('Sousou no Frieren', 'sousou no frieren!'), 1.0);
    });

    test('partial title scores moderate, not zero, not full', () {
      final s = titleSimilarity('frieren', 'Sousou no Frieren');
      expect(s, greaterThan(0.4));
      expect(s, lessThan(0.8));
    });

    test('unrelated titles score low', () {
      expect(
        titleSimilarity('Cowboy Bebop', 'Sousou no Frieren'),
        lessThan(0.3),
      );
    });
  });

  group('rankCandidates', () {
    test('picks the best title match, not the first candidate', () {
      final candidates = [
        _series(1, romaji: 'Fate/stay night: Unlimited Blade Works'),
        _series(2, romaji: 'Fate/Zero'),
        _series(3, romaji: 'Sousou no Frieren', english: "Frieren"),
      ];
      final result = rankCandidates('Sousou no Frieren', candidates);
      expect(result.series?.anilistId, 3);
      expect(result.score, greaterThan(0.9));
    });

    test('ignores a semantic false-positive even if present', () {
      // Mirrors the Fate -> "Unmei" MUSIC recon: ranking by title similarity
      // never picks it for a real Fate query.
      final candidates = [
        _series(10, romaji: 'Unmei'),
        _series(11, romaji: 'Fate/Zero'),
      ];
      final result = rankCandidates('Fate Zero', candidates);
      expect(result.series?.anilistId, 11);
    });

    test('below the floor returns no match', () {
      final candidates = [_series(1, romaji: 'Sousou no Frieren')];
      final result = rankCandidates('zzzqxwv nonsense', candidates);
      expect(result.series, isNull);
    });

    test('empty candidate list returns no match', () {
      final result = rankCandidates('anything', const []);
      expect(result.series, isNull);
      expect(result.score, 0);
    });
  });
}
