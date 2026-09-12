import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:anilocal/data/json_http.dart';
import 'package:anilocal/data/source_exception.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TestException extends SourceException {
  const _TestException(super.message, {super.failure});
}

/// The one request scaffold. Every client used to carry its own copy of these
/// rules; this pins them once.
void main() {
  final uri = Uri.parse('https://svc.test/thing');
  final slept = <Duration>[];
  JsonHttp make(http.Client client, {int maxRetries = 2}) => JsonHttp(
    client,
    service: 'Svc',
    fail: (m, {required failure}) => _TestException(m, failure: failure),
    maxRetries: maxRetries,
    sleep: (d) async => slept.add(d),
  );
  Future<MetadataFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on _TestException catch (e) {
      return e.failure;
    }
    fail('expected a failure');
  }

  setUp(slept.clear);

  group('retry', () {
    test('a 429 is retried, waiting what Retry-After asked', () async {
      var calls = 0;
      final json = make(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('slow down', 429, headers: {'retry-after': '3'})
              : http.Response('{"ok":true}', 200);
        }),
      );
      final body = await json.getJson(uri);
      expect(body['ok'], isTrue);
      expect(calls, 2);
      expect(slept, [const Duration(seconds: 3)]);
    });

    test('Retry-After as an HTTP-date is honoured', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final at = now.add(const Duration(seconds: 42));
      expect(
        JsonHttp.retryAfter(HttpDate.format(at), now: now),
        const Duration(seconds: 42),
      );
      expect(JsonHttp.retryAfter('garbage'), isNull);
      expect(JsonHttp.retryAfter(null), isNull);
    });

    test(
      'a 503 is retried with a backoff when the service says nothing',
      () async {
        var calls = 0;
        final json = make(
          MockClient((_) async {
            calls++;
            return calls < 3
                ? http.Response('', 503)
                : http.Response('{"ok":true}', 200);
          }),
        );
        await json.getJson(uri);
        expect(calls, 3);
        expect(slept, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      },
    );

    test('gives up after maxRetries and reports rate limiting', () async {
      var calls = 0;
      final json = make(
        MockClient((_) async {
          calls++;
          return http.Response('', 429);
        }),
      );
      expect(await failureOf(json.getJson(uri)), MetadataFailure.rateLimited);
      expect(calls, 3, reason: 'one try plus two retries');
    });

    test('an enormous Retry-After is capped', () async {
      var calls = 0;
      final json = make(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 429, headers: {'retry-after': '86400'})
              : http.Response('{}', 200);
        }),
      );
      await json.getJson(uri);
      expect(slept.single, const Duration(seconds: 10));
    });

    test('a 500 is NOT retried', () async {
      var calls = 0;
      final json = make(
        MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      expect(await failureOf(json.getJson(uri)), MetadataFailure.service);
      expect(calls, 1);
    });
  });

  group('attribution', () {
    test('no response at all is the connection', () async {
      final json = make(
        MockClient((_) async => throw http.ClientException('x')),
      );
      expect(await failureOf(json.getJson(uri)), MetadataFailure.connection);
    });

    test(
      'a 200 that is not JSON is a malformed response, not "down"',
      () async {
        final json = make(
          MockClient((_) async => http.Response('<html>', 200)),
        );
        expect(
          await failureOf(json.getJson(uri)),
          MetadataFailure.malformedResponse,
        );
      },
    );

    test('a 200 whose JSON is not an object is malformed too', () async {
      final json = make(MockClient((_) async => http.Response('[1,2]', 200)));
      expect(
        await failureOf(json.getJson(uri)),
        MetadataFailure.malformedResponse,
      );
    });

    test(
      'a 4xx with the service\'s envelope is the service; without, blocked',
      () async {
        String? envelope(String body) =>
            body.startsWith('{') ? 'svc says no' : null;
        final theirs = make(
          MockClient((_) async => http.Response('{"error":1}', 400)),
        );
        final between = make(
          MockClient((_) async => http.Response('<html>proxy</html>', 400)),
        );
        expect(
          await failureOf(theirs.getJson(uri, errorTextOf: envelope)),
          MetadataFailure.service,
        );
        expect(
          await failureOf(between.getJson(uri, errorTextOf: envelope)),
          MetadataFailure.blocked,
        );
      },
    );

    test('404 is a normal null for the callers that want it', () async {
      final json = make(MockClient((_) async => http.Response('', 404)));
      expect(await json.getJsonOrNull(uri), isNull);
      expect(await failureOf(json.getJson(uri)), MetadataFailure.blocked);
    });
  });

  test('every request carries a User-Agent and Accept, plus extras', () async {
    late Map<String, String> seen;
    final json = make(
      MockClient((req) async {
        seen = req.headers;
        return http.Response('{}', 200);
      }),
    );
    await json.getJson(uri, headers: {'X-Extra': '1'});
    expect(seen['User-Agent'], startsWith('AniLocal/'));
    expect(seen['Accept'], 'application/json');
    expect(seen['X-Extra'], '1');
  });

  test('postJson sends the body as JSON', () async {
    late String sent;
    final json = make(
      MockClient((req) async {
        sent = req.body;
        return http.Response('{}', 200);
      }),
    );
    await json.postJson(uri, body: {'q': 'x'});
    expect(jsonDecode(sent), {'q': 'x'});
  });
}
