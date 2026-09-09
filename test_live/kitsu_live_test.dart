import 'package:anilocal/data/kitsu/kitsu_client.dart';
import 'package:anilocal/domain/models/series_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the REAL [KitsuClient] against the real kitsu.io, to check the
/// fixtures in `kitsu_client_test.dart` still match what the service returns.
/// Mocked fixtures can only prove we parse what we THINK is returned.
///
/// Lives OUTSIDE `test/` on purpose — `flutter test` walks `test/` only, so
/// these never run in the normal suite. Run deliberately:
///
///   flutter test test_live/
///
/// Kitsu is reliable but SLOW (1.5–10s observed, occasional timeout), so each
/// call gets a few attempts — but the test FAILS rather than passes if it never
/// gets through, so it can't be vacuously green.
Future<T> _withRetries<T>(Future<T> Function() body, {int tries = 6}) async {
  Object? last;
  for (var i = 0; i < tries; i++) {
    try {
      return await body();
    } on KitsuException catch (e) {
      last = e;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
  throw StateError('Kitsu never answered in $tries attempts: $last');
}

void main() {
  test(
    'LIVE: search maps into the shape the client promises',
    () async {
      final client = KitsuClient();
      addTearDown(client.dispose);

      final results = await _withRetries(
        () => client.searchCandidates('Cowboy Bebop', perPage: 5),
      );

      expect(results, isNotEmpty);
      final bebop = results.firstWhere((s) => s.externalIds.kitsu == 1);
      expect(bebop.titles.romaji, 'Cowboy Bebop');
      // The charset trap: Kitsu sends raw UTF-8 with NO charset, so a regression
      // to `response.body` shows up here as mojibake.
      expect(bebop.titles.native, 'カウボーイビバップ');
      expect(bebop.episodeCount, 26);
      expect(bebop.format, kFormatTv);
      expect(bebop.coverImageRef, startsWith('https://'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'LIVE: include=mappings really resolves AniList and MAL ids',
    () async {
      // This is the load-bearing one. If Kitsu ever stops returning mappings
      // inline, every Kitsu-identified show would start minting its own identity
      // instead of landing on the AniList one — silently.
      final client = KitsuClient();
      addTearDown(client.dispose);

      final results = await _withRetries(
        () => client.searchCandidates('Cowboy Bebop', perPage: 5),
      );

      final bebop = results.firstWhere((s) => s.externalIds.kitsu == 1);
      expect(
        bebop.externalIds.anilist,
        isNotNull,
        reason: 'anilist/anime mapping',
      );
      expect(
        bebop.externalIds.mal,
        isNotNull,
        reason: 'myanimelist/anime mapping',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'LIVE: fetchByIds returns the same shape',
    () async {
      final client = KitsuClient();
      addTearDown(client.dispose);

      final results = await _withRetries(() => client.fetchByIds([1, 7442]));

      expect(results.length, 2);
      final ids = results.map((s) => s.externalIds.kitsu).toSet();
      expect(ids, {1, 7442});
      expect(results.every((s) => s.titles.romaji != null), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'LIVE: a nonsense query is a no-match, not an error',
    () async {
      final client = KitsuClient();
      addTearDown(client.dispose);

      final results = await _withRetries(
        () => client.searchCandidates('zzzzqqqxnotarealanime12345'),
      );

      expect(results, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
