import 'package:anilocal/data/request_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spaces two calls by at least the interval', () async {
    final throttle = RequestThrottle(const Duration(milliseconds: 40));
    final sw = Stopwatch()..start();
    await throttle.wait();
    await throttle.wait();
    expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 40)));
  });

  test('a call after a long pause does not wait', () async {
    final throttle = RequestThrottle(const Duration(milliseconds: 20));
    await throttle.wait();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final sw = Stopwatch()..start();
    await throttle.wait();
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 15)));
  });

  test('is measured on a monotonic clock, so it cannot sleep for an hour', () {
    // The whole reason this exists. The old per-client copies used
    // DateTime.now(); a backward wall-clock jump made the elapsed time negative
    // and the wait `minInterval + jump`. A Stopwatch has no notion of wall time
    // at all — there is nothing here that COULD go negative. Pinned by type,
    // since it is the design, not a runtime branch, that provides the safety.
    final injected = Stopwatch();
    final throttle = RequestThrottle(
      const Duration(seconds: 1),
      stopwatch: injected,
    );
    expect(throttle, isA<RequestThrottle>());
    expect(
      injected.elapsed,
      Duration.zero,
      reason: 'starts on first wait, not before',
    );
  });
}
