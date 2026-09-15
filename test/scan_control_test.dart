import 'dart:async';

import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_control.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:anilocal/ui/scan_control.dart';
import 'package:anilocal/ui/settings/panels/sources_panel.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/theme/xp_widgets.dart';
import 'package:anilocal/ui/widgets/header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';
import 'support/fake_sources.dart';

const _show = Series(
  seriesId: 1,
  titles: Titles(romaji: 'Show One'),
  format: 'TV',
  episodeCount: 12,
);

SyncSummary _summary({bool cancelled = false}) => SyncSummary(
  filesScanned: 4,
  unchanged: 0,
  processed: 4,
  removed: 0,
  matched: cancelled ? 2 : 4,
  unmatched: 0,
  errored: 0,
  lookupsBySource: const {},
  cancelled: cancelled,
);

/// A scan that reports progress and then waits to be stopped — the shape of
/// a 500-title scan against a dead network, which before this could not be
/// stopped at all.
Widget _app(ScanRunner onScan) => AniLocalApp(
  repository: FakeLibraryRepository(series: [_show]),
  fixMatch: const FakeFixMatch(),
  watchState: FakeLibraryRepository(),
  sourceSelection: FakeLibraryRepository(),
  watchOrder: FakeLibraryRepository(),
  playback: PlaybackController(resolver: FakeLibraryRepository()),
  missing: FakeLibraryRepository(),
  showPreferences: FakeLibraryRepository(),
  settings: const FakeSettings(),
  onScan: onScan,
  onRefreshMetadata: () async =>
      const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
  onAddFolder: () async => (added: false, deniedLabel: null),
  accessIssues: ValueNotifier<List<String>>(const []),
  missingFolders: ValueNotifier<List<String>>(const []),
  missingFolderPaths: ValueNotifier<Set<String>>(const {}),
  onOpenAccessSettings: () async => true,
  metadataSources: const [],
  skipSources: const [],
);

void main() {
  group('ScanControl', () {
    test('begin/report/stop/end: one token per run, progress republished', () {
      final control = ScanControl();
      expect(control.scanning.value, isFalse);
      final token = control.begin();
      expect(control.scanning.value, isTrue);
      expect(control.progress.value, isNull);
      control.report(
        const SyncProgress(done: 3, total: 9, phase: 'identifying'),
      );
      expect(control.progress.value?.done, 3);
      expect(token.isCancelled, isFalse);
      control.stop();
      expect(token.isCancelled, isTrue, reason: 'Stop cancels THIS run');
      control.end();
      expect(control.scanning.value, isFalse);
      expect(control.progress.value, isNull);
      control.stop(); // idle: nothing to cancel, nothing thrown
      expect(control.stopRequested, isFalse);
    });
  });

  group('the header while a scan runs', () {
    Widget bar({
      required bool scanning,
      SyncProgress? progress,
      VoidCallback? stop,
    }) => MaterialApp(
      theme: XpTheme.data(),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          child: HeaderActionsBar(
            scanning: scanning,
            unmatchedCount: 0,
            onScan: () async {},
            onUnmatched: () {},
            onSettings: () {},
            progress: progress,
            onStopScan: stop,
          ),
        ),
      ),
    );

    testWidgets('idle: Scan; running: Stop, with the progress in reach', (
      tester,
    ) async {
      await tester.pumpWidget(bar(scanning: false));
      expect(find.byTooltip('Scan library folders'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

      var stopped = 0;
      await tester.pumpWidget(
        bar(
          scanning: true,
          progress: const SyncProgress(
            done: 120,
            total: 600,
            phase: 'identifying',
          ),
          stop: () => stopped++,
        ),
      );
      expect(find.byIcon(Icons.sync), findsNothing, reason: 'Scan is Stop now');
      final stop = find.byIcon(Icons.stop_circle_outlined);
      expect(stop, findsOneWidget);
      expect(
        find.byTooltip(
          'Stop scanning — identifying 120 of 600 (keeps what has been identified)',
        ),
        findsOneWidget,
      );
      await tester.tap(stop);
      expect(stopped, 1);
    });
  });

  group('Stop through the app', () {
    testWidgets('cancels the running scan; the summary says stopped early', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SyncCancellation? seen;
      final started = Completer<void>();
      await tester.pumpWidget(
        _app((onDiscovered, {onProgress, cancellation}) async {
          seen = cancellation;
          onProgress?.call(
            const SyncProgress(done: 1, total: 4, phase: 'identifying'),
          );
          started.complete();
          // Wait until Stop is pressed — the pipeline checks the token at
          // every loop head; this stands in for that.
          while (!cancellation!.isCancelled) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          return _summary(cancelled: true);
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byTooltip('Scan library folders'));
      await tester.pump();
      await started.future;
      await tester.pump();

      expect(seen, isNotNull, reason: 'the UI hands the pipeline a token');
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      // The readout is dot-matrix (painted, not Text), so read its title.
      expect(
        tester.widget<HeaderReadout>(find.byType(HeaderReadout)).title,
        contains('identifying 1/4'),
        reason: 'the readout carries the progress',
      );

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      // The fake scan polls every 10ms; let it notice and return.
      for (var i = 0; i < 10 && !seen!.isCancelled; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(seen!.isCancelled, isTrue);
      expect(find.byIcon(Icons.sync), findsOneWidget, reason: 'back to Scan');
      expect(find.textContaining('stopped early'), findsOneWidget);
    });
  });

  group('actions gated while a scan runs', () {
    testWidgets('Folders: Add and Remove are disabled and say why', (
      tester,
    ) async {
      final scanning = ValueNotifier<bool>(false);
      final repo = FakeSourcesRepository(['/lib/a', '/lib/b']);
      await tester.pumpWidget(
        MaterialApp(
          theme: XpTheme.data(),
          home: Scaffold(
            body: SourcesPanel(
              sources: fakeSourcesActions(repo, scanning: scanning),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // XpButton wraps its own Tooltip, so the button is the tooltip's
      // ancestor.
      XpButton buttonWithTooltip(String tooltip) => tester.widget<XpButton>(
        find
            .ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(XpButton),
            )
            .first,
      );
      XpButton addButton() => buttonWithTooltip('Add folder');
      expect(addButton().onPressed, isNotNull);

      scanning.value = true;
      await tester.pump();
      expect(
        buttonWithTooltip('Wait for the scan to finish').onPressed,
        isNull,
      );
      expect(
        find.byTooltip('Wait for the scan to finish'),
        findsNWidgets(3),
        reason: 'Add plus one Remove per folder',
      );

      scanning.value = false;
      await tester.pump();
      expect(addButton().onPressed, isNotNull, reason: 'live, not a snapshot');
    });
  });
}
