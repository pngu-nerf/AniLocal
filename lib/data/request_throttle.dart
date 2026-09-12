/// Spaces requests to a rate-limited service at least [minInterval] apart.
///
/// ONE implementation, shared by the clients that need it (Jikan documents
/// 3 req/s, MAL ~1 req/s), instead of the byte-identical private copy each used
/// to carry. Measured on a [Stopwatch], NOT the wall clock: the previous copies
/// used `DateTime.now()`, so a backward clock jump (NTP correction, a VM
/// resume, a manual change) made the elapsed time negative and the wait
/// `minInterval + jump` — an hour-long sleep in the middle of a scan, with no
/// cancel. A stopwatch cannot run backwards.
///
/// Callers are SERIALISED: two concurrent `wait()`s queue rather than both
/// reading the same "last request" stamp and firing together — which is what
/// happened when a fix-match search ran during a scan on the shared client.
///
/// The stopwatch is injectable so tests can drive it without sleeping.
class RequestThrottle {
  RequestThrottle(this.minInterval, {Stopwatch? stopwatch})
    : _clock = stopwatch ?? Stopwatch();

  final Duration minInterval;
  final Stopwatch _clock;
  Duration? _lastRequestAt;
  Future<void> _gate = Future<void>.value();

  /// Wait until at least [minInterval] has passed since the previous call
  /// completed its wait — including calls that are still waiting.
  Future<void> wait() {
    final mine = _gate.then((_) => _space());
    // The chain must survive a caller that never awaits: an error here would
    // otherwise poison every later wait.
    _gate = mine.catchError((Object _) {});
    return mine;
  }

  Future<void> _space() async {
    if (!_clock.isRunning) _clock.start();
    final last = _lastRequestAt;
    if (last != null) {
      final since = _clock.elapsed - last;
      if (since < minInterval) await Future<void>.delayed(minInterval - since);
    }
    _lastRequestAt = _clock.elapsed;
  }
}
