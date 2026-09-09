import 'package:anilocal/data/jikan/jikan_client.dart';
import 'package:anilocal/domain/models/series_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the REAL [JikanClient] against the real api.jikan.moe, to check the
/// fixtures in `jikan_client_test.dart` still match what the service returns.
/// Mocked fixtures can only ever prove we parse what we THINK is returned.
///
/// Lives OUTSIDE `test/` on purpose. `flutter test` only walks `test/`, so
/// these never run in the normal suite — a suite whose result depends on a
/// third party's uptime stops meaning anything. (Tags don't work here: the
/// preset flag that would re-include them is `dart test -P`, which
/// `flutter test` doesn't accept.) Run deliberately:
///
///   flutter test test_live/
///
/// Retries, because Jikan is intermittent — but FAILS rather than passes when
/// it never gets through, so it can never be vacuously green.
Future<T> _withRetries<T>(Future<T> Function() body, {int tries = 120}) async {
  Object? last;
  for (var i = 0; i < tries; i++) {
    try {
      return await body();
    } on JikanException catch (e) {
      last = e;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
  throw StateError('Jikan never answered in $tries attempts: $last');
}

void main() {
  test(
    'LIVE: search maps into the shape the client promises',
    () async {
      final client = JikanClient();
      addTearDown(client.dispose);

      final results = await _withRetries(
        () => client.searchCandidates('Cowboy Bebop', perPage: 3),
      );

      expect(results, isNotEmpty);
      final bebop = results.firstWhere((s) => s.externalIds.mal == 1);
      expect(bebop.titles.romaji, 'Cowboy Bebop');
      // The charset trap: if we regressed to response.body this is mojibake.
      expect(bebop.titles.native, 'カウボーイビバップ');
      expect(bebop.episodeCount, 26);
      expect(bebop.format, kFormatTv, reason: "MAL's 'TV' normalises");
      expect(bebop.coverImageRef, startsWith('https://'));
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test(
    'LIVE: fetchByIds returns the same shape',
    () async {
      final client = JikanClient();
      addTearDown(client.dispose);

      final results = await _withRetries(() => client.fetchByIds([1]));

      expect(results.single.externalIds.mal, 1);
      expect(results.single.titles.native, 'カウボーイビバップ');
      expect(results.single.format, kFormatTv);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
