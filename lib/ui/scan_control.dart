import 'package:flutter/foundation.dart';

import '../domain/models/sync_control.dart';

/// The one place the UI holds "a scan is running": the flag every header
/// disables its Scan button on, the progress the readout shows, and the
/// cancellation the Stop button pulls. App-lifetime; owned by `_AppLifetime`
/// and handed to every screen through `LibraryServices`.
///
/// Before this the flag alone existed. `SyncCancellation` and `SyncProgress`
/// were built and tested in the pipeline but nothing in the UI ever
/// constructed one, so a 500-title scan against a dead network — hours of
/// timeouts — could not be stopped, and its only cue was a spinner.
/// How long a page waits after a progress report before re-reading its data
/// while a scan runs — reports arrive per title, reloads are per-show reads.
const Duration kScanReloadDebounce = Duration(milliseconds: 500);

class ScanControl {
  ScanControl({ValueNotifier<bool>? scanning})
    : scanning = scanning ?? ValueNotifier<bool>(false);

  /// True while a scan runs. Listened to by every header.
  final ValueNotifier<bool> scanning;

  /// The last progress report of the running scan; null when idle or before
  /// the first report (the readout shows nothing specific then).
  final ValueNotifier<SyncProgress?> progress = ValueNotifier(null);

  SyncCancellation? _current;

  /// Mark a scan started and hand back the token to give the pipeline. The
  /// caller MUST pair it with [end] in a `finally`.
  SyncCancellation begin() {
    scanning.value = true;
    progress.value = null;
    return _current = SyncCancellation();
  }

  /// The running scan reported progress; republished to every header.
  void report(SyncProgress p) => progress.value = p;

  void end() {
    _current = null;
    progress.value = null;
    scanning.value = false;
  }

  /// The Stop button. Everything committed so far stays; the pipeline stops
  /// at its next checkpoint and the summary says `cancelled`.
  void stop() => _current?.cancel();

  bool get stopRequested => _current?.isCancelled ?? false;

  void dispose() {
    progress.dispose();
    scanning.dispose();
  }
}
