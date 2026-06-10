import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = HeuristicFilenameParser();

  group('HeuristicFilenameParser', () {
    test('standard SubsPlease release: group, title, episode', () {
      final p = parser.parse(
        '[SubsPlease] Sousou no Frieren - 01 (1080p) [F02D9AE6].mkv',
      );
      expect(p.releaseGroup, 'SubsPlease');
      expect(p.title, 'Sousou no Frieren');
      expect(p.episodeNumber, 1);
    });

    test('keeps numbers inside the title (dash is the episode signal)', () {
      final p = parser.parse(
        '[Erai-raws] Mob Psycho 100 III - 05 [1080p][Multiple Subtitle].mkv',
      );
      expect(p.releaseGroup, 'Erai-raws');
      expect(p.title, 'Mob Psycho 100 III');
      expect(p.episodeNumber, 5);
    });

    test('no group, internal hyphen in title stays intact', () {
      final p = parser.parse('Kaguya-sama wa Kokurasetai - 03.mkv');
      expect(p.releaseGroup, isNull);
      expect(p.title, 'Kaguya-sama wa Kokurasetai');
      expect(p.episodeNumber, 3);
    });

    test('dotted scene name with S00E00 + codec noise', () {
      final p = parser.parse('Show.Name.S02E05.1080p.WEB-DL.x264.mkv');
      expect(p.title, 'Show Name');
      expect(p.seasonNumber, 2);
      expect(p.episodeNumber, 5);
    });

    test('version suffix on episode', () {
      final p = parser.parse('[Group] Title Name - 12v2 [720p].mkv');
      expect(p.title, 'Title Name');
      expect(p.episodeNumber, 12);
    });

    test('three-digit episode', () {
      final p = parser.parse(
        '[HorribleSubs] Boku no Hero Academia - 88 [480p].mkv',
      );
      expect(p.title, 'Boku no Hero Academia');
      expect(p.episodeNumber, 88);
    });

    test('trailing bare number with following resolution noise', () {
      final p = parser.parse('One.Piece.1071.1080p.mkv');
      expect(p.title, 'One Piece');
      expect(p.episodeNumber, 1071);
    });

    test('movie with year: no episode, year is not mistaken for one', () {
      final p = parser.parse('[Group] Some Movie Title (2020) [BD 1080p].mkv');
      expect(p.title, 'Some Movie Title');
      expect(p.episodeNumber, isNull);
    });

    test('S01E12 with spaces around marker', () {
      final p = parser.parse('[Judas] Spy x Family - S01E12 [1080p].mkv');
      expect(p.title, 'Spy x Family');
      expect(p.seasonNumber, 1);
      expect(p.episodeNumber, 12);
    });

    test('title with punctuation preserved enough to search', () {
      final p = parser.parse('Bocchi the Rock! - 08.mkv');
      expect(p.title, 'Bocchi the Rock!');
      expect(p.episodeNumber, 8);
    });
  });
}
