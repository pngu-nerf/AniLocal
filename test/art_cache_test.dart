import 'dart:io';

import 'package:anilocal/data/cache/art_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The cover store had no unit test of its own: reuse, replacement on a
/// changed URL, the partial-write hole, concurrent callers, the extension
/// rule and the sweep were all untested.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_art_');
  });
  tearDown(() => dir.delete(recursive: true));

  ArtCache cache(MockClient client) =>
      ArtCache(httpClient: client, directory: () async => dir);

  MockClient serving(List<int> bytes, {void Function(http.Request)? onCall}) =>
      MockClient((req) async {
        onCall?.call(req);
        return http.Response.bytes(bytes, 200);
      });

  test('downloads once, then reuses the file', () async {
    var calls = 0;
    final art = cache(serving([1, 2, 3], onCall: (_) => calls++));
    final a = await art.ensureCover(7, 'https://cdn.test/7.jpg');
    final b = await art.ensureCover(7, 'https://cdn.test/7.jpg');
    expect(a, '${dir.path}/7.jpg');
    expect(b, a);
    expect(calls, 1);
    expect(File(a!).readAsBytesSync(), [1, 2, 3]);
  });

  test(
    'a changed source URL replaces the file and drops the old one',
    () async {
      final art = cache(serving([9]));
      final first = await art.ensureCover(7, 'https://a.test/7.jpg');
      final second = await art.ensureCover(
        7,
        'https://b.test/7.png',
        cachedUrl: 'https://a.test/7.jpg',
        cachedPath: first,
      );
      expect(second, '${dir.path}/7.png');
      expect(File(first!).existsSync(), isFalse, reason: 'superseded');
    },
  );

  test('a failed or empty download leaves NO file behind', () async {
    final empty = cache(MockClient((_) async => http.Response.bytes([], 200)));
    expect(await empty.ensureCover(7, 'https://cdn.test/7.jpg'), isNull);
    final failing = cache(
      MockClient((_) async => throw http.ClientException('boom')),
    );
    expect(await failing.ensureCover(8, 'https://cdn.test/8.jpg'), isNull);
    expect(dir.listSync(), isEmpty, reason: 'no partial file, no .part');
  });

  test('two callers wanting the same cover share ONE download', () async {
    var calls = 0;
    final art = cache(serving([1], onCall: (_) => calls++));
    final paths = await Future.wait([
      art.ensureCover(7, 'https://cdn.test/7.jpg'),
      art.ensureCover(7, 'https://cdn.test/7.jpg'),
    ]);
    expect(calls, 1);
    expect(paths.first, paths.last);
  });

  test('only a known image extension is kept; anything else is .jpg', () async {
    final art = cache(serving([1]));
    expect(
      await art.ensureCover(1, 'https://cdn.test/x.WEBP?size=large'),
      '${dir.path}/1.webp',
    );
    expect(
      await art.ensureCover(2, 'https://cdn.test/img.a/b'),
      '${dir.path}/2.jpg',
      reason: 'a path fragment must not become a subdirectory',
    );
  });

  test('every request carries a User-Agent', () async {
    String? ua;
    final art = cache(
      serving([1], onCall: (r) => ua = r.headers['User-Agent']),
    );
    await art.ensureCover(1, 'https://cdn.test/1.jpg');
    expect(ua, startsWith('AniLocal/'));
  });

  test('deleteExcept removes covers for series no longer cached', () async {
    final art = cache(serving([1]));
    await art.ensureCover(1, 'https://cdn.test/1.jpg');
    await art.ensureCover(2, 'https://cdn.test/2.jpg');
    File('${dir.path}/.DS_Store').writeAsStringSync('x'); // not ours
    final removed = await art.deleteExcept({1});
    expect(removed, 1);
    expect(File('${dir.path}/1.jpg').existsSync(), isTrue);
    expect(File('${dir.path}/2.jpg').existsSync(), isFalse);
    expect(File('${dir.path}/.DS_Store').existsSync(), isTrue);
  });
}
