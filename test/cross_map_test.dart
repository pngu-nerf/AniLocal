import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/crossmap/cross_map_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The cross-map exists so AniSkip stops depending on AniList being reachable.
/// Its whole contract is "never make anything worse": every failure path must
/// yield an empty or stale map, never an exception and never a wrong id.
void main() {
  late Directory dir;
  Future<Directory> dirFn() async => dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_crossmap_');
  });
  tearDown(() async => dir.delete(recursive: true));

  /// A slice of the upstream shape, including rows we must tolerate: an entry
  /// with no AniList id, and one with no ids we care about.
  String upstream() => jsonEncode([
    {'anilist_id': 290, 'mal_id': 290, 'kitsu_id': 265, 'tvdb_id': 72025},
    {'anilist_id': 105156, 'mal_id': 38659, 'kitsu_id': 41889},
    {'anilist_id': 999, 'kitsu_id': 4321}, // kitsu only, no mal
    {'anidb_id': 7, 'tvdb_id': 1}, // no anilist id at all
    {'anilist_id': 555}, // nothing worth storing
  ]);

  MockClient okClient(void Function()? onCall) => MockClient((_) async {
    onCall?.call();
    return http.Response(upstream(), 200);
  });

  test('fetches, derives, and answers both id lookups', () async {
    final store = CrossMapStore(httpClient: okClient(null), directory: dirFn);

    final map = await store.load();

    expect(map.malFor(290), 290);
    expect(map.kitsuFor(290), 265);
    expect(map.malFor(105156), 38659);
    expect(map.malFor(999), isNull, reason: 'kitsu-only row has no mal');
    expect(map.kitsuFor(999), 4321);
    expect(
      map.malFor(555),
      isNull,
      reason: 'row with no usable ids is skipped',
    );
    expect(map.malFor(12345), isNull, reason: 'unknown id is simply unknown');
  });

  test('a second load hits the disk cache, not the network', () async {
    var calls = 0;
    final first = CrossMapStore(
      httpClient: okClient(() => calls++),
      directory: dirFn,
    );
    await first.load();
    expect(calls, 1);

    // A NEW store instance, so the in-memory memo can't be what answers.
    final second = CrossMapStore(
      httpClient: okClient(() => calls++),
      directory: dirFn,
    );
    final map = await second.load();

    expect(calls, 1, reason: 'fresh disk cache must not refetch');
    expect(map.malFor(290), 290);
  });

  test('a stale cache is refetched', () async {
    var calls = 0;
    final seed = CrossMapStore(
      httpClient: okClient(() => calls++),
      directory: dirFn,
    );
    await seed.load(now: DateTime(2026, 1, 1));

    final later = CrossMapStore(
      httpClient: okClient(() => calls++),
      directory: dirFn,
      maxAge: const Duration(days: 7),
    );
    await later.load(now: DateTime(2026, 1, 20));

    expect(calls, 2);
  });

  test(
    'a failed fetch with no cache degrades to empty, never throws',
    () async {
      final store = CrossMapStore(
        httpClient: MockClient((_) async => http.Response('nope', 503)),
        directory: dirFn,
      );

      final map = await store.load();

      // Empty means every lookup returns null, which is exactly the behaviour
      // callers had before the map existed — degraded, never wrong.
      expect(map.isEmpty, isTrue);
      expect(map.malFor(290), isNull);
    },
  );

  test('offline transport degrades to empty, never throws', () async {
    final store = CrossMapStore(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
      directory: dirFn,
    );

    await expectLater(store.load(), completion(isNotNull));
    expect((await store.load()).isEmpty, isTrue);
  });

  test('a STALE cache still answers when the refetch fails', () async {
    await CrossMapStore(
      httpClient: okClient(null),
      directory: dirFn,
    ).load(now: DateTime(2026, 1, 1));

    final offline = CrossMapStore(
      httpClient: MockClient((_) async => http.Response('', 500)),
      directory: dirFn,
    );
    final map = await offline.load(now: DateTime(2026, 6, 1)); // long stale

    // Ids don't change and the list only grows, so stale beats nothing.
    expect(map.malFor(290), 290);
  });

  test('a corrupt cache file is re-derived rather than crashing', () async {
    await File('${dir.path}/crossmap.json').writeAsString('{not json');

    final map = await CrossMapStore(
      httpClient: okClient(null),
      directory: dirFn,
    ).load();

    expect(map.malFor(290), 290);
  });

  test('a body that is not the expected shape yields empty', () async {
    final store = CrossMapStore(
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'unexpected': true}), 200),
      ),
      directory: dirFn,
    );

    expect((await store.load()).isEmpty, isTrue);
  });
}
