import '../domain/models/metadata_failure.dart';

/// A per-run circuit breaker for the sources a scan asks.
///
/// A source that cannot be REACHED fails the same way for every title: a
/// 30-second timeout, then the next source. Without this, a blackholed
/// network cost ~90 s per new title (three providers × the timeout) and a
/// 500-title first scan was twelve hours of waiting for nothing. After
/// [threshold] consecutive transport failures a source is DOWN for the rest
/// of the run and is not asked again; the summary names it. Only transport
/// failures count — a 429 is retried by the client, a 5xx or a no-match is
/// an answer — and any success resets the count.
///
/// Per RUN on purpose: the next scan asks again, because the network may be
/// back.
class SourceHealth {
  SourceHealth({this.threshold = 2});

  /// Consecutive transport failures before a source is treated as down.
  final int threshold;

  final Map<String, int> _consecutive = {};
  final Set<String> _down = {};

  bool isDown(String token) => _down.contains(token);

  /// Sources marked down this run, sorted, for the summary.
  List<String> get down => _down.toList()..sort();

  void succeeded(String token) => _consecutive.remove(token);

  void failed(String token, MetadataFailure? failure) {
    // Only "could not reach it" is a property of the run rather than of the
    // request: connection (no answer) and blocked (something in between
    // refused the handshake).
    if (failure != MetadataFailure.connection &&
        failure != MetadataFailure.blocked) {
      _consecutive.remove(token);
      return;
    }
    final n = (_consecutive[token] ?? 0) + 1;
    _consecutive[token] = n;
    if (n >= threshold) _down.add(token);
  }
}
