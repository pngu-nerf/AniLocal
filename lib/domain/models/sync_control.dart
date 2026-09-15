import 'metadata_failure.dart';
import 'sync_summary.dart';
import 'user_facing_failure.dart';

/// How the UI runs a scan: the composition root supplies one of these.
/// `onDiscovered` fires once phase 1 has written placeholders; `onProgress`
/// after each committed batch; `cancellation` stops the run at its next
/// checkpoint, keeping everything committed so far.
typedef ScanRunner =
    Future<SyncSummary> Function(
      void Function() onDiscovered, {
      void Function(SyncProgress progress)? onProgress,
      SyncCancellation? cancellation,
    });

/// Cooperative cancellation for a scan or a metadata refresh.
///
/// The fill path checks [isCancelled] at the head of every loop that does
/// network or disk work and stops there, keeping everything it has already
/// COMMITTED (work is written in batches) and leaving the rest exactly as a
/// scan that had never run: new files stay the pending placeholders phase 1
/// wrote, so the next scan picks them up. Before this existed a first scan of
/// a large library against two dead services was hours of un-cancellable work.
class SyncCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Throws [SyncCancelled] if [cancel] has been called.
  void throwIfCancelled() {
    if (_cancelled) throw const SyncCancelled();
  }
}

/// Raised inside the fill path at a cancellation point; caught there and
/// turned into a summary with `cancelled: true`. Never reaches the UI.
class SyncCancelled implements Exception {
  const SyncCancelled();
}

/// A second scan or refresh was started while one was running.
///
/// The fill path is the ONE writer of the cache and is not reentrant; the UI
/// disables the controls while a run is in flight, so this surfaces only a
/// race, loudly, rather than two runs interleaving writes over one database.
class SyncAlreadyRunning implements Exception, UserFacingFailure {
  const SyncAlreadyRunning();

  @override
  MetadataFailure? get failure => null;

  @override
  String get userMessage =>
      'A scan or refresh is already running — wait for it to finish.';

  @override
  String toString() => 'SyncAlreadyRunning: a scan or refresh is in progress';
}

/// How far a scan or refresh has got, for a progress affordance.
///
/// [done] and [total] count the units of the current [phase] — titles
/// identified so far, episodes asked for skips, series refreshed. Reported
/// per unit so the counter moves; writes land per BATCH, so on Stop the
/// unfinished batch's titles are re-identified next scan (nothing is lost:
/// their placeholders are already on disk).
class SyncProgress {
  const SyncProgress({
    required this.done,
    required this.total,
    required this.phase,
  });

  final int done;
  final int total;
  final String phase;

  @override
  String toString() => '$phase $done/$total';
}
