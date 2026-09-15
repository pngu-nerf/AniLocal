import 'dart:async';

import 'package:anilocal/sync/library_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bounded pool cover downloads run through: at most `limit` in flight,
/// results in input order whatever order they finish in.
void main() {
  group('mapLimited', () {
    test('never exceeds the limit and preserves order', () async {
      var inFlight = 0, peak = 0;
      final gates = <int, Completer<void>>{};
      final run = mapLimited(List.generate(10, (i) => i), 4, (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        gates[i] = Completer<void>();
        await gates[i]!.future;
        inFlight--;
        return 'r$i';
      });
      await Future<void>.delayed(Duration.zero);
      expect(inFlight, 4, reason: 'four started, the fifth waits');
      // Release out of order: the pool refills, the result order does not move.
      for (final i in [2, 0, 3, 1, 5, 4, 7, 6, 9, 8]) {
        while (!gates.containsKey(i)) {
          await Future<void>.delayed(Duration.zero);
        }
        gates[i]!.complete();
        await Future<void>.delayed(Duration.zero);
      }
      expect(await run, [for (var i = 0; i < 10; i++) 'r$i']);
      expect(peak, 4);
    });

    test('fewer items than the limit: one worker each, nothing idle', () async {
      expect(await mapLimited([1, 2], 4, (i) async => i * 2), [2, 4]);
      expect(await mapLimited(<int>[], 4, (i) async => i), isEmpty);
    });
  });
}
