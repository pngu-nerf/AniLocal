import 'dart:async';

import 'package:anilocal/data/anilist/anilist_client.dart';
import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/jikan/jikan_client.dart';
import 'package:anilocal/data/kitsu/kitsu_client.dart';
import 'package:anilocal/data/mal/mal_client.dart';
import 'package:anilocal/data/timeout_client.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// An inner client whose `send` never completes: the half-open socket.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// An inner client that returns headers at once and then a body that emits
/// one chunk and goes silent forever: the stalled download that a plain
/// `send().timeout()` would NOT catch.
class _StallingBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    controller.add([123]); // "{" — one chunk, then nothing, ever
    return http.StreamedResponse(controller.stream, 200, request: request);
  }
}

const _short = Duration(milliseconds: 50);

void main() {
  group('TimeoutClient', () {
    test('a request that never returns headers fails within the timeout', () {
      final client = TimeoutClient(_HangingClient(), timeout: _short);
      expect(
        client.get(Uri.parse('https://example.test/')),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('a body that stalls after its first chunk fails too', () {
      // The case the header-phase timeout alone misses, and the reason the
      // body stream is wrapped separately.
      final client = TimeoutClient(_StallingBodyClient(), timeout: _short);
      expect(
        client.get(Uri.parse('https://example.test/')),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('the default timeout is the one measured against Kitsu', () {
      // Named so a change is a decision, not a drift. Asserted against the
      // constant so the value can move without silently invalidating this.
      expect(TimeoutClient(_HangingClient()).timeout, kHttpTimeout);
      expect(kHttpTimeout, greaterThanOrEqualTo(const Duration(seconds: 10)));
    });
  });

  group('every client turns a hang into MetadataFailure.connection', () {
    // No client was changed for this: each already mapped any Exception from
    // the transport to `connection`. Pinned per client anyway, because "the
    // wrapper throws the right type" and "the client keeps mapping it" are two
    // facts, and a refactor could break the second while the first holds.
    final hung = TimeoutClient(_HangingClient(), timeout: _short);

    Future<void> expectConnection(Future<Object?> Function() call) async {
      Object? caught;
      try {
        await call();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'must fail, not hang');
      final failure = switch (caught) {
        AniListException e => e.failure,
        KitsuException e => e.failure,
        JikanException e => e.failure,
        MalException e => e.failure,
        AniSkipException e => e.failure,
        _ => null,
      };
      expect(failure, MetadataFailure.connection, reason: '$caught');
    }

    test(
      'AniList',
      () => expectConnection(
        () => AniListClient(
          httpClient: hung,
        ).searchSeriesCandidates('cowboy bebop'),
      ),
    );
    test(
      'Kitsu',
      () => expectConnection(
        () => KitsuClient(httpClient: hung).searchCandidates('cowboy bebop'),
      ),
    );
    test(
      'Jikan',
      () => expectConnection(
        () => JikanClient(
          httpClient: hung,
          minInterval: Duration.zero,
        ).searchCandidates('cowboy bebop'),
      ),
    );
    test(
      'MAL',
      () => expectConnection(
        () => MalClient(
          httpClient: hung,
          minInterval: Duration.zero,
          loadClientId: () async => 'key',
        ).searchCandidates('cowboy bebop'),
      ),
    );
    test(
      'AniSkip',
      () => expectConnection(
        () => AniSkipClient(httpClient: hung).fetchSkips(1, 1),
      ),
    );
  });
}
