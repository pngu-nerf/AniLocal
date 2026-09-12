import 'package:anilocal/data/scanner/title_matching.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:flutter_test/flutter_test.dart';

Series _series(int id, {String? romaji, String? english}) => Series(
  seriesId: id,
  titles: Titles(romaji: romaji, english: english),
);

void main() {
  group('normalizeTitle', () {
    test('lowercases, strips punctuation, collapses whitespace', () {
      expect(normalizeTitle('Sousou no Frieren!'), 'sousou no frieren');
      expect(normalizeTitle('Re:ZERO  -Starting-'), 're zero starting');
    });

    test('keeps letters of every script — a native title is not empty', () {
      // The ASCII whitelist this replaced normalised every Japanese title to
      // '', so all such files collapsed into one lookup and one series.
      expect(normalizeTitle('葬送のフリーレン'), '葬送のフリーレン');
      expect(normalizeTitle('Re：ゼロから始める異世界生活！'), 're ゼロから始める異世界生活');
      expect(normalizeTitle('Атака титанов'), 'атака титанов');
    });
  });

  group('non-Latin titles match like any other', () {
    test('two identical native titles score 1, two different ones do not', () {
      expect(titleSimilarity('葬送のフリーレン', '葬送のフリーレン'), 1.0);
      expect(titleSimilarity('葬送のフリーレン', '進撃の巨人'), lessThan(0.5));
    });

    test(
      'a native-titled file ranks the candidate whose native title matches',
      () {
        final candidates = [
          Series(
            seriesId: 1,
            titles: const Titles(romaji: 'Shingeki no Kyojin', native: '進撃の巨人'),
          ),
          Series(
            seriesId: 2,
            titles: const Titles(
              romaji: 'Sousou no Frieren',
              native: '葬送のフリーレン',
            ),
          ),
        ];
        expect(rankCandidates('葬送のフリーレン', candidates).series?.seriesId, 2);
      },
    );
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
      expect(result.series?.seriesId, 3);
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
      expect(result.series?.seriesId, 11);
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
