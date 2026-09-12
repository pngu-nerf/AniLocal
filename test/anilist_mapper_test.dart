import 'package:anilocal/data/anilist/anilist_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mapper reads guarded, never casts. A cast on `dynamic` throws a
/// TypeError — an Error — which escaped every `on Exception` on the scan path
/// and aborted the run before the cache-preserving outage guard could act.
void main() {
  group('seriesFromMediaJson', () {
    test('fields of the wrong shape are null, not fatal', () {
      final s = seriesFromMediaJson({
        'id': 7,
        'idMal': '123', // a string where an int belongs
        'title': 'not an object',
        'format': 42,
        'episodes': '12',
        'coverImage': <String, Object?>{'extraLarge': 9},
        'relations': <String, Object?>{'edges': 'nope'},
      });
      expect(s.seriesId, 7);
      expect(s.externalIds.mal, isNull);
      expect(s.titles.romaji, isNull);
      expect(s.format, isNull);
      expect(s.episodeCount, isNull);
      expect(s.coverImageRef, isNull);
      expect(s.relations, isEmpty);
    });

    test(
      'a non-integer id is the one fatal case, and it is a FormatException',
      () {
        expect(
          () => seriesFromMediaJson({'id': '7'}),
          throwsA(isA<FormatException>()),
          reason: 'an Exception the client maps, not an Error that escapes',
        );
        expect(() => seriesFromMediaJson({}), throwsA(isA<FormatException>()));
      },
    );

    test('a relation edge without a node id is skipped', () {
      final s = seriesFromMediaJson({
        'id': 1,
        'relations': {
          'edges': [
            null,
            <String, Object?>{'node': null},
            {
              'node': {'id': 'x'},
            },
            {
              'relationType': 'SEQUEL',
              'node': {'id': 2, 'format': 'TV'},
            },
          ],
        },
      });
      expect(s.relations, hasLength(1));
      expect(s.relations.single.anilistId, 2);
    });
  });

  test('seriesListFromMediaList skips entries that are not objects', () {
    final list = seriesListFromMediaList([
      null,
      'junk',
      {'id': 3},
    ]);
    expect(list.map((s) => s.seriesId), [3]);
  });
}
