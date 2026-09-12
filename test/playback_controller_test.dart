import 'dart:async';

import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:anilocal/domain/repositories/watch_order_repository.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_player.dart';

class _Resolver implements WatchOrderRepository {
  _Resolver(this.next);
  final Episode? next;
  int asked = 0;
  Completer<void>? gate;

  @override
  Future<Map<int, Episode>> upNextBySeries() => throw UnimplementedError();

  @override
  Future<NextResult> nextEpisode(Episode current) async {
    asked++;
    await gate?.future;
    final n = next;
    return n == null ? const NoNextEpisode() : NextEpisode(n);
  }
}

const _ep1 = Episode(number: 1, fileRef: '/s/01.mkv', anchoredNumber: 1);
const _ep2 = Episode(number: 2, fileRef: '/s/02.mkv', anchoredNumber: 2);

/// The controller's two contracts that used to be doc-only: one advance at a
/// time, and a dispose that is the end.
void main() {
  group('PlaybackController', () {
    test(
      'concurrent advances join the one in flight — one resolve, one open',
      () async {
        final player = RecordingPlayer();
        final resolver = _Resolver(_ep2)..gate = Completer<void>();
        final playback = PlaybackController.withPlayer(
          player,
          resolver: resolver,
        );
        await playback.open(_ep1);
        player.opened.clear();

        // The countdown, the completion event and a held → key all land at once.
        final a = playback.advanceToNext();
        final b = playback.advanceToNext();
        final c = playback.advanceToNext();
        resolver.gate!.complete();
        final results = await Future.wait([a, b, c]);

        expect(results, everyElement(_ep2));
        expect(resolver.asked, 1, reason: '"next" resolved once from ep 1');
        expect(
          player.opened.map((m) => m.uri),
          ['/s/02.mkv'],
          reason: 'ep 2 opened once, not three times — and ep 3 never',
        );
        expect(playback.current, _ep2);
      },
    );

    test(
      'after an advance completes the next call is a fresh advance',
      () async {
        final player = RecordingPlayer();
        final resolver = _Resolver(_ep2);
        final playback = PlaybackController.withPlayer(
          player,
          resolver: resolver,
        );
        await playback.open(_ep1);
        await playback.advanceToNext();
        await playback.advanceToNext();
        expect(resolver.asked, 2);
      },
    );

    test('a season boundary stops and returns null', () async {
      final playback = PlaybackController.withPlayer(
        RecordingPlayer(),
        resolver: _Resolver(null),
      );
      await playback.open(_ep1);
      expect(await playback.advanceToNext(), isNull);
      expect(playback.current, _ep1);
    });

    test(
      'dispose is terminal: later use throws instead of rebuilding',
      () async {
        final player = RecordingPlayer();
        final playback = PlaybackController.withPlayer(
          player,
          resolver: _Resolver(null),
        );
        await playback.dispose();
        expect(player.called(#dispose), isTrue);
        expect(() => playback.player, throwsStateError);
        expect(() => playback.open(_ep1), throwsStateError);
        await playback.dispose(); // idempotent
      },
    );

    test('stop keeps the engine and forgets the episode', () async {
      final player = RecordingPlayer();
      final playback = PlaybackController.withPlayer(
        player,
        resolver: _Resolver(null),
      );
      await playback.open(_ep1);
      await playback.stop();
      expect(player.called(#stop), isTrue);
      expect(player.called(#dispose), isFalse);
      expect(playback.current, isNull);
      expect(playback.player, same(player));
    });
  });
}
