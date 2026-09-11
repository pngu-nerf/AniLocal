import 'dart:async';

import 'package:http/http.dart' as http;

/// How long any single request may take to return headers, and how long its
/// body may then go SILENT between chunks, before it is treated as failed.
///
/// Measured against the slowest source we ship to, not chosen: Kitsu answers in
/// 1.5–10s when healthy, so 30s is three times its worst observed case. The
/// number exists because `package:http` has NO default timeout — a half-open
/// socket or a stalled body would otherwise hang a scan forever, with no cancel
/// and no progress, and (worse) hang it BEFORE the "service is down, keep the
/// cache" guard, which only runs once the loop finishes.
const Duration kHttpTimeout = Duration(seconds: 30);

/// The ONE place a request can time out.
///
/// A decorator around any [http.Client], so every client in the app inherits
/// the same limit by being handed this from the composition root instead of
/// building its own. Two phases are bounded separately: [send] itself (time to
/// headers) and the response body (time between chunks — a server that sends
/// headers and then stalls is the case a plain `send().timeout()` misses).
///
/// Both failures surface as [http.ClientException], which is what every client
/// already maps to `MetadataFailure.connection` — so adding this required no
/// change to any of them. `MetadataFailure.connection`'s doc listed "timeout"
/// as a case it covered; until this existed, that case could never occur.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(this._inner, {this.timeout = kHttpTimeout});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner
        .send(request)
        .timeout(
          timeout,
          onTimeout: () => throw http.ClientException(
            'No response within ${timeout.inSeconds}s',
            request.url,
          ),
        );
    return http.StreamedResponse(
      response.stream.timeout(
        timeout,
        onTimeout: (sink) {
          sink.addError(
            http.ClientException(
              'Response body stalled for ${timeout.inSeconds}s',
              request.url,
            ),
          );
          sink.close();
        },
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
