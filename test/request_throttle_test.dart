import 'dart:async';

import 'package:anilocal/data/request_throttle.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stopwatch the test advances by hand. `RequestThrottle` reads only
/// `isRunning`, `start()` and `elapsed`, so this is the whole surface.
class _ManualStopwatch extends Stopwatch {
  Duration _now = Duration.zero;
  bool _running = false;

  void advance(Duration by) => _now += by;

  @override
  Duration get elapsed => _now;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
}

void main() {
  group('RequestThrottle', () {
    const interval = Duration(seconds: 1);

    test('the second call waits out the remainder of the interval', () {
      fakeAsync((async) {
        final clock = _ManualStopwatch();
        final throttle = RequestThrottle(interval, stopwatch: clock);
        var done = 0;
        unawaited(throttle.wait().then((_) => done++));
        async.flushMicrotasks();
        expect(done, 1, reason: 'the first call never waits');

        clock.advance(const Duration(milliseconds: 400));
        unawaited(throttle.wait().then((_) => done++));
        async.elapse(const Duration(milliseconds: 599));
        expect(done, 1, reason: 'still inside the interval');
        async.elapse(const Duration(milliseconds: 1));
        expect(done, 2, reason: 'exactly the remainder, no longer');
      });
    });

    test('time is read from the STOPWATCH, so a long gap means no wait', () {
      // The discriminating case. FakeAsync does not fake `DateTime.now()`, so an
      // implementation on the wall clock would see no time pass here and sleep
      // for the full interval; the injected stopwatch says an hour has passed.
      // This is the test that fails if anyone puts `DateTime.now()` back.
      fakeAsync((async) {
        final clock = _ManualStopwatch();
        final throttle = RequestThrottle(interval, stopwatch: clock);
        unawaited(throttle.wait());
        async.flushMicrotasks();

        clock.advance(const Duration(hours: 1));
        var done = false;
        unawaited(throttle.wait().then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isTrue, reason: 'no timer was ever scheduled');
      });
    });

    test('two CONCURRENT callers are spaced, not fired together', () {
      // Both used to read the same "last request" stamp, compute the same
      // delay and fire at once — which is exactly what a fix-match search during
      // a scan did on the shared Jikan client.
      fakeAsync((async) {
        final clock = _ManualStopwatch();
        final throttle = RequestThrottle(interval, stopwatch: clock);
        var first = false;
        var second = false;
        unawaited(throttle.wait().then((_) => first = true));
        unawaited(throttle.wait().then((_) => second = true));
        async.flushMicrotasks();
        expect(first, isTrue);
        expect(second, isFalse, reason: 'queued behind the first');
        async.elapse(interval);
        expect(second, isTrue);
      });
    });

    test('the wait is bounded by the interval whatever the clock says', () {
      // A monotonic stopwatch cannot go backwards — that is the property that
      // replaced `DateTime.now()`, whose backward jump produced a wait of
      // `interval + jump`. The bound is therefore structural; this pins the
      // arithmetic at the edge: zero elapsed → wait exactly one interval.
      fakeAsync((async) {
        final clock = _ManualStopwatch();
        final throttle = RequestThrottle(interval, stopwatch: clock);
        unawaited(throttle.wait());
        async.flushMicrotasks();
        var done = false;
        unawaited(throttle.wait().then((_) => done = true));
        async.elapse(interval - const Duration(microseconds: 1));
        expect(done, isFalse);
        async.elapse(const Duration(microseconds: 1));
        expect(done, isTrue);
      });
    });
  });
}
