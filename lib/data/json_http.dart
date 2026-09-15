import 'dart:convert';
import 'dart:io' show HandshakeException, HttpDate;

import 'package:http/http.dart' as http;

import '../domain/models/metadata_failure.dart';
import 'http_failure.dart';
import 'request_throttle.dart';
import 'source_exception.dart';
import 'user_agent.dart';

/// Builds the caller's own exception type from what went wrong.
typedef SourceExceptionFactory =
    SourceException Function(
      String message, {
      required MetadataFailure failure,
    });

/// The service's own error text from a failure body, or null when the body is
/// not the service's envelope — which doubles as the "did the service write
/// this?" test that decides between `service` and `blocked`.
typedef ErrorTextOf = String? Function(String body);

/// A source-specific override of the shared status classification (MAL reads
/// its error envelope to tell a bad key from throttling).
typedef FailureClassifier = MetadataFailure Function(int status, String body);

/// The ONE request scaffold every JSON service shares.
///
/// Five clients used to carry a byte-identical copy of this: build the
/// request, catch transport failure as `connection`, decode the BYTES as
/// UTF-8 (never `response.body` — with no `charset` in the content type,
/// package:http falls back to latin1 and mojibakes every Japanese title),
/// classify a non-200, decode JSON guarded (a 200 carrying an HTML
/// interstitial must be a malformed-response failure, not a bare
/// `FormatException` past every catch upstream), and check the shape. Changing
/// any of that policy meant editing five files; now it is here.
///
/// It also owns two things none of the copies had:
///
/// * **Retry with `Retry-After`.** A 429 or 503 is retried up to [maxRetries]
///   times, waiting what the service asked for (seconds or an HTTP-date,
///   capped at [maxRetryDelay]) or a short backoff when it said nothing.
///   Before this a single 429 abandoned the source for the whole run. Reads
///   only — every request here is idempotent, so a retry cannot double-write.
/// * **Spacing**, via an optional [RequestThrottle], so a client with a
///   documented rate limit declares it once at construction.
class JsonHttp {
  JsonHttp(
    this._http, {
    required this.service,
    required this.fail,
    this.throttle,
    this.maxRetries = 2,
    this.maxRetryDelay = const Duration(seconds: 10),
    this._sleep = _realSleep,
  });

  final http.Client _http;

  /// Human name for messages ("AniList request failed: …").
  final String service;
  final SourceExceptionFactory fail;
  final RequestThrottle? throttle;
  final int maxRetries;
  final Duration maxRetryDelay;
  final Future<void> Function(Duration) _sleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// GET, expecting a JSON object.
  Future<Map<String, dynamic>> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
    ErrorTextOf? errorTextOf,
    FailureClassifier? classify,
  }) async {
    final decoded = await _request(
      () => _http.get(uri, headers: _headers(headers)),
      errorTextOf: errorTextOf,
      classify: classify,
    );
    return _asObject(decoded);
  }

  /// GET where a 404 means "the service has nothing for this key" — a normal
  /// answer, returned as null — rather than a failure.
  Future<Map<String, dynamic>?> getJsonOrNull(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final decoded = await _request(
      () => _http.get(uri, headers: _headers(headers)),
      nullOn404: true,
    );
    return decoded == null ? null : _asObject(decoded);
  }

  /// GET, returning whatever JSON value the body holds (a list, say).
  Future<Object?> getAny(Uri uri, {Map<String, String> headers = const {}}) =>
      _request(() => _http.get(uri, headers: _headers(headers)));

  /// POST a JSON body, expecting a JSON object back.
  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Object body,
    Map<String, String> headers = const {},
    ErrorTextOf? errorTextOf,
  }) async {
    final decoded = await _request(
      () => _http.post(
        uri,
        headers: _headers({'Content-Type': 'application/json', ...headers}),
        body: jsonEncode(body),
      ),
      errorTextOf: errorTextOf,
    );
    return _asObject(decoded);
  }

  Map<String, String> _headers(Map<String, String> extra) => {
    'Accept': 'application/json',
    // A named UA: AniList's Cloudflare returns 403 to package:http's default,
    // and the volunteer-run services deserve to know who is asking.
    'User-Agent': aniLocalUserAgent,
    ...extra,
  };

  Future<Object?> _request(
    Future<http.Response> Function() send, {
    ErrorTextOf? errorTextOf,
    FailureClassifier? classify,
    bool nullOn404 = false,
  }) async {
    http.Response response;
    for (var attempt = 0; ; attempt++) {
      await throttle?.wait();
      try {
        response = await send();
      } on HandshakeException catch (e) {
        // TLS was refused or intercepted: a proxy, a VPN, a captive portal,
        // a clock so wrong the certificate reads as invalid. The connection
        // itself worked, so "check your internet" would send the user the
        // wrong way — `blocked` names something in between.
        throw fail(
          'TLS handshake with $service failed: $e',
          failure: MetadataFailure.blocked,
        );
      } on Exception catch (e) {
        // No HTTP response at all: the request never reached the service, so
        // the fault is on this side of the wire — DNS, refused, timed out.
        throw fail(
          'Network error contacting $service: $e',
          failure: MetadataFailure.connection,
        );
      }
      final status = response.statusCode;
      final retryable = status == 429 || status == 503;
      if (!retryable || attempt >= maxRetries) break;
      await _sleep(_retryDelay(response, attempt));
    }

    if (nullOn404 && response.statusCode == 404) return null;
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      final detail = errorTextOf?.call(body);
      throw fail(
        detail == null
            ? '$service request failed: HTTP ${response.statusCode}.'
            : '$service request failed: HTTP ${response.statusCode} — $detail',
        failure:
            classify?.call(response.statusCode, body) ??
            classifyHttpFailure(
              response.statusCode,
              carriesProviderError: detail != null,
            ),
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      throw fail(
        'Malformed $service response: $e',
        failure: MetadataFailure.malformedResponse,
      );
    }
  }

  Map<String, dynamic> _asObject(Object? decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    throw fail(
      'Unexpected $service response shape.',
      failure: MetadataFailure.malformedResponse,
    );
  }

  /// What the service asked us to wait, or a short backoff when it did not.
  Duration _retryDelay(http.Response response, int attempt) {
    final asked = retryAfter(response.headers['retry-after']);
    final delay = asked ?? Duration(seconds: 1 << attempt);
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }

  /// Parse a `Retry-After` header: delay-seconds, or an HTTP-date (RFC 7231).
  /// Null when absent or unreadable. Never negative.
  static Duration? retryAfter(String? header, {DateTime? now}) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
    try {
      final at = HttpDate.parse(header.trim());
      final delta = at.difference(now ?? DateTime.now());
      return delta.isNegative ? Duration.zero : delta;
    } on Exception {
      return null;
    }
  }

  /// Decode a body leniently, for error-envelope readers: null when it is not
  /// JSON at all.
  static Object? tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
