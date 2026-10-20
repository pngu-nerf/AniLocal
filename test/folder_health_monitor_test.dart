import 'dart:async';

import 'package:anilocal/data/folders/folder_health_monitor.dart';
import 'package:anilocal/data/folders/folder_health_probe.dart';
import 'package:anilocal/diagnostics/app_log.dart';
import 'package:anilocal/domain/folder_health.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The folder-health monitor: WHEN the probe runs and WHAT changed. The probe
/// itself is scripted — a report per pass, optionally slow — so the timing
/// rules are exercised on FakeAsync's clock, which the monitor reads through
/// its injected `now` (FakeAsync does not fake `DateTime.now()`).
void main() {
  const a = '/Volumes/USB/Anime';
  const b = '/Users/me/Anime';
  final t0 = DateTime(2026, 9, 23, 12);

  FolderHealthReport report(Map<String, FolderAccessState> states) =>
      FolderHealthReport(
        stateByPath: states,
        missingPaths: {
          for (final e in states.entries)
            if (e.value == FolderAccessState.missing) e.key,
        },
      );

  final allUp = report({
    a: FolderAccessState.accessible,
    b: FolderAccessState.accessible,
  });
  final usbGone = report({
    a: FolderAccessState.missing,
    b: FolderAccessState.accessible,
  });

  setUp(AppLog.reset);

  group('diffFolderHealth', () {
    test('a state change is one event; add/remove is none', () {
      final changes = diffFolderHealth(
        {a: FolderAccessState.accessible, b: FolderAccessState.missing},
        {
          a: FolderAccessState.missing, // pulled
          b: FolderAccessState.missing, // unchanged
          '/new': FolderAccessState.accessible, // just added
        },
        t0,
      );
      expect(changes, [
        FolderAvailabilityChange(
          path: a,
          from: FolderAccessState.accessible,
          to: FolderAccessState.missing,
          at: t0,
        ),
      ]);
      expect(changes.single.isDisconnect, isTrue);
      expect(changes.single.isReconnect, isFalse);

      final back = diffFolderHealth(
        {a: FolderAccessState.missing},
        {a: FolderAccessState.accessible},
        t0,
      );
      expect(back.single.isReconnect, isTrue);
      // A removed folder is nobody's drive event.
      expect(diffFolderHealth({a: FolderAccessState.missing}, {}, t0), isEmpty);
    });
  });

  group('FolderHealthMonitor', () {
    /// A monitor over a scripted probe. [script] is consumed one report per
    /// pass (the last one repeats); [passTakes] delays each pass on the fake
    /// clock so the backoff can be exercised.
    ({
      FolderHealthMonitor monitor,
      List<FolderAvailabilityChange> changes,
      List<FolderHealthReport> reports,
      int Function() passes,
    })
    harness(
      FakeAsync async,
      List<FolderHealthReport> script, {
      Duration passTakes = Duration.zero,
      bool Function()? paused,
    }) {
      final clock = async.getClock(t0);
      var passes = 0;
      final monitor = FolderHealthMonitor(
        probe: () async {
          final r = script[passes < script.length ? passes : script.length - 1];
          passes++;
          if (passTakes > Duration.zero) await Future<void>.delayed(passTakes);
          return r;
        },
        paused: paused,
        now: clock.now,
      );
      final changes = <FolderAvailabilityChange>[];
      final reports = <FolderHealthReport>[];
      monitor.changes.listen(changes.add);
      monitor.reports.listen(reports.add);
      return (
        monitor: monitor,
        changes: changes,
        reports: reports,
        passes: () => passes,
      );
    }

    test('the first pass is a baseline: a report, no events', () {
      fakeAsync((async) {
        final h = harness(async, [usbGone]);
        unawaited(h.monitor.refresh());
        async.flushMicrotasks();
        expect(h.reports, hasLength(1));
        expect(h.monitor.latest?.missingPaths, {a});
        expect(h.changes, isEmpty, reason: 'already-missing is state');
        expect(h.monitor.lastPassAt, t0);
      });
    });

    test('a drive pulled, then plugged back, is two events in order', () {
      fakeAsync((async) {
        final h = harness(async, [allUp, usbGone, allUp]);
        unawaited(h.monitor.refresh());
        async.flushMicrotasks();
        unawaited(h.monitor.refresh());
        async.flushMicrotasks();
        expect(h.changes, hasLength(1));
        expect(h.changes.single.path, a);
        expect(h.changes.single.isDisconnect, isTrue);
        // The report carrying the new state landed BEFORE the event.
        expect(h.reports.last.missingPaths, {a});

        unawaited(h.monitor.refresh());
        async.flushMicrotasks();
        expect(h.changes, hasLength(2));
        expect(h.changes.last.isReconnect, isTrue);
        expect(h.monitor.latest?.missingPaths, isEmpty);
        expect(
          AppLog.recent(),
          anyElement(contains('$a missing → accessible')),
        );
      });
    });

    test('the timer polls every interval once started', () {
      fakeAsync((async) {
        final h = harness(async, [allUp, allUp, usbGone]);
        unawaited(h.monitor.refresh()); // the launch pass
        async.flushMicrotasks();
        h.monitor.start();
        h.monitor.start(); // idempotent: one timer, not two
        expect(h.passes(), 1);
        async.elapse(kFolderHealthPollInterval);
        expect(h.passes(), 2);
        async.elapse(kFolderHealthPollInterval);
        expect(h.passes(), 3);
        expect(h.changes.single.isDisconnect, isTrue);

        h.monitor.stop();
        async.elapse(kFolderHealthPollInterval * 3);
        expect(h.passes(), 3, reason: 'stopped: no more ticks');
        expect(h.monitor.isRunning, isFalse);
      });
    });

    test('a tick while paused (a scan runs) is skipped, not queued', () {
      fakeAsync((async) {
        var scanning = true;
        final h = harness(async, [allUp], paused: () => scanning);
        h.monitor.start();
        async.elapse(kFolderHealthPollInterval * 3);
        expect(h.passes(), 0);
        scanning = false;
        async.elapse(kFolderHealthPollInterval);
        expect(h.passes(), 1, reason: 'resumes on the next tick');
        // refresh() itself is never paused: the scan calls it.
        scanning = true;
        unawaited(h.monitor.refresh());
        async.flushMicrotasks();
        expect(h.passes(), 2);
      });
    });

    test('passes never overlap: refresh() joins one in flight', () {
      fakeAsync((async) {
        final h = harness(async, [
          allUp,
        ], passTakes: const Duration(seconds: 2));
        h.monitor.start();
        final first = h.monitor.refresh();
        final second = h.monitor.refresh();
        expect(identical(first, second), isTrue, reason: 'joined, not doubled');
        async.elapse(const Duration(seconds: 2));
        expect(h.passes(), 1);
        // A tick that lands mid-pass is skipped and re-armed, not queued.
        async.elapse(const Duration(seconds: 27)); // t = 29 s
        unawaited(h.monitor.refresh()); // runs 29–31 s; the tick is due at 30
        async.elapse(const Duration(seconds: 2)); // t = 31 s
        expect(h.passes(), 2, reason: 'the tick joined nothing and ran none');
        async.elapse(kFolderHealthPollInterval); // t = 61 s
        expect(h.passes(), 3, reason: 'the re-armed tick ran');
      });
    });

    test('a slow pass backs the timer off, doubling to a cap', () {
      fakeAsync((async) {
        // Every pass takes one full probe timeout: the wedged-share case.
        final h = harness(async, [allUp], passTakes: kFolderHealthSlowPass);
        h.monitor.start();
        async.elapse(kFolderHealthPollInterval); // tick 1 fires at 30 s
        async.elapse(kFolderHealthSlowPass); // …and takes 5 s
        expect(h.passes(), 1);
        // Next gap is 2× the interval, measured from the pass's end.
        async.elapse(kFolderHealthPollInterval);
        expect(h.passes(), 1, reason: 'backed off: 30 s is not enough');
        async.elapse(kFolderHealthPollInterval + kFolderHealthSlowPass);
        expect(h.passes(), 2);
        // 4×, 8× … capped at kFolderHealthMaxBackoff.
        async.elapse(kFolderHealthPollInterval * 4 + kFolderHealthSlowPass);
        expect(h.passes(), 3);
        async.elapse(kFolderHealthPollInterval * 8 + kFolderHealthSlowPass);
        expect(h.passes(), 4);
        async.elapse(kFolderHealthMaxBackoff + kFolderHealthSlowPass);
        expect(h.passes(), 5, reason: '16× would be 8 min; the cap is 5');
        expect(AppLog.recent(), anyElement(contains('a folder timed out')));
      });
    });

    test('a fast pass after slow ones resets the cadence', () {
      fakeAsync((async) {
        var slow = true;
        final monitor = FolderHealthMonitor(
          probe: () async {
            if (slow) await Future<void>.delayed(kFolderHealthSlowPass);
            return allUp;
          },
          now: async.getClock(t0).now,
        );
        var passes = 0;
        monitor.reports.listen((_) => passes++);
        monitor.start();
        async.elapse(kFolderHealthPollInterval + kFolderHealthSlowPass);
        expect(passes, 1);
        slow = false;
        async.elapse(kFolderHealthPollInterval * 2);
        expect(passes, 2, reason: 'the one backed-off gap');
        async.elapse(kFolderHealthPollInterval);
        expect(passes, 3, reason: 'back to every interval');
        monitor.stop();
      });
    });

    test('a probe that throws is logged and the timer keeps going', () {
      fakeAsync((async) {
        var fail = true;
        final monitor = FolderHealthMonitor(
          probe: () async {
            if (fail) throw StateError('db closed');
            return allUp;
          },
          now: async.getClock(t0).now,
        );
        var passes = 0;
        monitor.reports.listen((_) => passes++);
        monitor.start();
        async.elapse(kFolderHealthPollInterval);
        expect(passes, 0);
        expect(AppLog.recent(), anyElement(contains('poll failed')));
        fail = false;
        async.elapse(kFolderHealthPollInterval);
        expect(passes, 1);
        monitor.stop();
        // refresh() propagates its own error to the caller.
        fail = true;
        expect(monitor.refresh(), throwsStateError);
        async.flushMicrotasks();
      });
    });
  });
}
