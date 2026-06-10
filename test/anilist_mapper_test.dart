import 'dart:convert';

import 'package:anilocal/data/anilist/anilist_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seriesFromMediaJson', () {
    test('maps titles, format, episodes, cover, and relations', () {
      final media = jsonDecode(_sampleMediaJson) as Map<String, dynamic>;

      final series = seriesFromMediaJson(media);

      expect(series.anilistId, 154587);
      expect(series.titles.romaji, 'Sousou no Frieren');
      expect(series.titles.english, 'Frieren: Beyond Journey\'s End');
      expect(series.titles.native, '葬送のフリーレン');
      expect(series.format, 'TV');
      expect(series.episodeCount, 28);
      // Prefers the largest available cover image.
      expect(series.coverImageRef, contains('extraLarge'));

      expect(series.relations, hasLength(2));
      expect(series.relations.first.relationType, 'ADAPTATION');
      expect(series.relations.first.titles.romaji, 'Sousou no Frieren');
      expect(series.relations.first.format, 'MANGA');
      expect(series.relations[1].relationType, 'SIDE_STORY');
    });

    test('tolerates missing optional fields', () {
      final media = <String, dynamic>{
        'id': 1,
        'title': {'romaji': 'Only Romaji', 'english': null, 'native': null},
      };

      final series = seriesFromMediaJson(media);

      expect(series.anilistId, 1);
      expect(series.titles.romaji, 'Only Romaji');
      expect(series.format, isNull);
      expect(series.episodeCount, isNull);
      expect(series.coverImageRef, isNull);
      expect(series.relations, isEmpty);
    });
  });
}

const String _sampleMediaJson = '''
{
  "id": 154587,
  "format": "TV",
  "episodes": 28,
  "title": {
    "romaji": "Sousou no Frieren",
    "english": "Frieren: Beyond Journey's End",
    "native": "葬送のフリーレン"
  },
  "coverImage": {
    "extraLarge": "https://example.com/extraLarge.jpg",
    "large": "https://example.com/large.jpg",
    "medium": "https://example.com/medium.jpg",
    "color": "#e4a15d"
  },
  "relations": {
    "edges": [
      {
        "relationType": "ADAPTATION",
        "node": {
          "id": 127779,
          "format": "MANGA",
          "type": "MANGA",
          "title": {
            "romaji": "Sousou no Frieren",
            "english": null,
            "native": "葬送のフリーレン"
          }
        }
      },
      {
        "relationType": "SIDE_STORY",
        "node": {
          "id": 169470,
          "format": "TV_SHORT",
          "type": "ANIME",
          "title": {
            "romaji": "Side Story",
            "english": null,
            "native": null
          }
        }
      }
    ]
  }
}
''';
