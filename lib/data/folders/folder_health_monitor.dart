import 'dart:async';
import 'dart:math' as math;

import '../../diagnostics/app_log.dart';
import '../../domain/folder_health.dart';
import 'folder_access.dart' show kFolderProbeTimeout;
import 'folder_health_probe.dart';

/// How often the monitor probes the library folders when nothing else asks.
///
/// Chosen with the NAS in mind, not the USB drive: each pass is a root stat
/// (and, for a category-protected folder, one directory read) per folder, and
/// on a network share that stat wakes nothing — a NAS answers a root stat
/// from its cache without spinning its disks — but it is still traffic, and
/// twice a minute is the rate that stays invisible on a home network. A drive
/// pulled or plugged back in is therefore noticed within about 30 s; the
/// scan's own two passes and [FolderHealthMonitor.refresh] are the ways to
/// know sooner, and a native mount notification (macOS `NSWorkspace`) is the
/// planned accelerator — it calls `refresh()`, nothing else.
const Duration kFolderHealthPollInterval = Duration(seconds: 30);

/// The longest the monitor waits between passes while a folder keeps timing
/// out (a wedged network mount); see `_scheduleNext`.
const Duration kFolderHealthMaxBackoff = Duration(minutes: 5);

/// A pass that took at least this long hit a probe timeout — the proxy the
/// backoff keys on, see `_scheduleNext`.
const Duration kFolderHealthSlowPass = kFolderProbeTimeout;

/// The live watch over the library folders' drives: the detection bones a
/// drive disconnect / reconnect produces events from.
///
/// It owns nothing about WHAT health is — that is [FolderHealthProbe] — only
/// WHEN it is asked and what changed since last time. Three rules:
///
/// - **One ingest point.** Every pass — the launch pass, the scan's start and
///   end passes, the timer's tick, a future native mount notification, a
///   Retry button — goes through [refresh], which probes, diffs against the
///   previous report, publishes the report, then the changes. A transition a
///   scan's end pass catches is therefore emitted exactly like one the timer
///   catches, and there is no second place a state could come from.
/// - **The first report is a baseline.** A drive already missing at launch is
///   state (the reconnect banner shows it), not a transition; no event.
/// - **Passes never overlap.** A hung mount holds a probe for up to
///   [kFolderProbeTimeout] per folder, and its underlying stat keeps a native
///   IO thread until the kernel gives up long after the timeout returned to
///   Dart. A tick that arrives while a pass is in flight is skipped, a
///   [refresh] during one joins it, and a slow pass backs the next tick off —
///   so a wedged share costs one blocked thread per pass, not one per tick.
class FolderHealthMonitor {
  FolderHealthMonitor({
    required this._probe,
    this.interval = kFolderHealthPollInterval,
    bool Function()? paused,
    this._now = DateTime.now,
  }) : _paused = paused ?? (() => false);

  final Future<FolderHealthReport> Function() _probe;

  /// The steady-state gap between passes; the backoff doubles from here.
  final Duration interval;

  /// While true the timer's ticks are skipped (a scan is running: it probes at
  /// its own start and end). [refresh] is never paused.
  final bool Function() _paused;

  /// Injected clock — FakeAsync does not fake `DateTime.now()`, and the pass
  /// duration the backoff reads must follow the test's clock.
  final DateTime Function() _now;

  final _reports = StreamController<FolderHealthReport>.broadcast();
  final _changes = StreamController<FolderAvailabilityChange>.broadcast();

  FolderHealthReport? _latest;
  DateTime? _lastPassAt;
  Future<FolderHealthReport>? _inFlight;
  Timer? _timer;
  bool _started = false;
  int _slowPasses = 0;

  /// The most recent report, or null before the first pass lands. The state
  /// the banners and the greying read; a diagnostics report prints it.
  FolderHealthReport? get latest => _latest;

  /// When [latest] was taken.
  DateTime? get lastPassAt => _lastPassAt;

  /// Every report, as it lands — the composition root publishes its sets from
  /// here, wholesale, so the greying and the banners cannot disagree.
  Stream<FolderHealthReport> get reports => _reports.stream;

  /// Every per-folder transition — THE hook: alerts, an automatic scan on
  /// reconnect and the player's live switch-back subscribe here. Emitted
  /// after the report that carries the new state, so a subscriber reacting to
  /// a change already sees [latest] updated.
  Stream<FolderAvailabilityChange> get changes => _changes.stream;

  /// Whether the timer is armed.
  bool get isRunning => _started;

  /// One pass now. A pass already in flight is joined, not doubled. Errors
  /// from the probe propagate to the caller (and the timer logs its own).
  Future<FolderHealthReport> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final pass = _pass();
    // Cleared when the pass ends, however it ends, BEFORE the caller resumes,
    // so a caller that refreshes again from its continuation starts a new
    // pass rather than joining the finished one.
    _inFlight = pass.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<FolderHealthReport> _pass() async {
    final started = _now();
    final report = await _probe();
    final at = _now();
    final took = at.difference(started);
    // Backoff proxy: a pass that took at least one probe timeout hit at least
    // one — the probe reports no timeouts of its own, and the duration is
    // enough to know a share is wedged. A pass under the timeout answered
    // everything, so the cadence returns to normal.
    if (took >= kFolderHealthSlowPass) {
      _slowPasses++;
      AppLog.warnRepeated(
        'folder-health-slow',
        'Folder health: a pass took ${took.inSeconds}s — a folder timed out',
      );
    } else {
      _slowPasses = 0;
    }
    final previous = _latest;
    _latest = report;
    _lastPassAt = at;
    _reports.add(report);
    if (previous != null) {
      for (final change in diffFolderHealth(
        previous.stateByPath,
        report.stateByPath,
        at,
      )) {
        AppLog.info(
          'Folder health: ${change.path} '
          '${change.from.name} → ${change.to.name}',
        );
        _changes.add(change);
      }
    }
    return report;
  }

  /// Arm the timer. Idempotent. The first tick is one [interval] away — the
  /// caller has just run (or is running) the launch pass itself.
  void start() {
    if (_started) return;
    _started = true;
    _scheduleNext();
  }

  /// Disarm the timer. A pass in flight completes and publishes; no further
  /// tick is scheduled. Idempotent; [start] re-arms.
  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// [stop], then close the streams. For tests and a full teardown; the app
  /// only ever calls [stop] (its quit hook).
  Future<void> dispose() async {
    stop();
    await _reports.close();
    await _changes.close();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!_started) return;
    // interval × 2^n, capped: 30 s, 1 min, 2 min, 4 min, 5 min, 5 min…
    final factor = math.pow(2, math.min(_slowPasses, 10)).toInt();
    final delay = interval * factor;
    _timer = Timer(
      delay > kFolderHealthMaxBackoff ? kFolderHealthMaxBackoff : delay,
      _tick,
    );
  }

  void _tick() {
    _timer = null;
    if (!_started) return;
    if (_paused() || _inFlight != null) {
      // A scan is probing for us, or the last pass is still out: try again
      // one interval later rather than pile on.
      _scheduleNext();
      return;
    }
    unawaited(
      refresh()
          .catchError((Object e, StackTrace s) {
            AppLog.warn('Folder health: poll failed', error: e, stack: s);
            return _latest ?? const FolderHealthReport();
          })
          .whenComplete(_scheduleNext),
    );
  }
}
