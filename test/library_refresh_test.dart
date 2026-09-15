import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';

const _summary = SyncSummary(
  filesScanned: 1,
  unchanged: 0,
  processed: 1,
  removed: 0,
  matched: 1,
  unmatched: 0,
  errored: 0,
  lookupsBySource: {},
);

Series _s(int id, String title) => Series(
  seriesId: id,
  titles: Titles(romaji: title),
);

void main() {
  group('library refresh', () {
    testWidgets('library grid re-reads the cache after a scan completes', (
      tester,
    ) async {
      // A realistic window, not the 800x600 default: the test font is much wider
      // than the real one, so at the default size the header's action tabs eat
      // the centred VFD screen and its title starts scrolling — and a running
      // marquee makes pumpAndSettle time out.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeLibraryRepository(
        series: [_s(1, 'Alpha')],
        folders: ['/a'],
      );

      await tester.pumpWidget(
        AniLocalApp(
          repository: repo,
          fixMatch: const FakeFixMatch(),
          watchState: repo,
          sourceSelection: repo,
          missing: repo,
          showPreferences: repo,
          settings: const FakeSettings(),
          watchOrder: repo,
          playback: PlaybackController(resolver: repo),
          onScan: (_, {onProgress, cancellation}) async {
            // A scan that adds a new series to the cache.
            repo.series = [_s(1, 'Alpha'), _s(2, 'Bravo')];
            return _summary;
          },
          onRefreshMetadata: () async =>
              const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
          onAddFolder: () async => (added: false, deniedLabel: null),
          accessIssues: ValueNotifier<List<String>>(const []),
          missingFolders: ValueNotifier<List<String>>(const []),
          missingFolderPaths: ValueNotifier<Set<String>>(const {}),
          categoryLabelOf: (_) => null,
          onOpenAccessSettings: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsNothing);

      await tester.tap(find.byTooltip('Scan library folders'));
      await tester.pumpAndSettle();

      expect(
        find.text('Bravo'),
        findsOneWidget,
        reason: 'grid must reflect the post-scan cache',
      );
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('a refresh NEVER blanks the grid — content stays on screen and '
        'no spinner appears', (tester) async {
      // The flash: _reload() used to re-assign the FutureBuilder's future, which
      // reset it to `waiting`, so the whole layout — grid, panel, search field —
      // was replaced by a centred spinner for a frame and rebuilt. That also
      // dropped the grid's scroll position. A refresh must update in place.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeLibraryRepository(
        series: [_s(1, 'Alpha')],
        folders: ['/a'],
      );
      await tester.pumpWidget(
        AniLocalApp(
          repository: repo,
          fixMatch: const FakeFixMatch(),
          watchState: repo,
          sourceSelection: repo,
          missing: repo,
          showPreferences: repo,
          settings: const FakeSettings(),
          watchOrder: repo,
          playback: PlaybackController(resolver: repo),
          onScan: (_, {onProgress, cancellation}) async {
            repo.series = [_s(1, 'Alpha'), _s(2, 'Bravo')];
            return _summary;
          },
          onRefreshMetadata: () async =>
              const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
          onAddFolder: () async => (added: false, deniedLabel: null),
          accessIssues: ValueNotifier<List<String>>(const []),
          missingFolders: ValueNotifier<List<String>>(const []),
          missingFolderPaths: ValueNotifier<Set<String>>(const {}),
          categoryLabelOf: (_) => null,
          onOpenAccessSettings: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);

      // Kick off a refresh and watch EVERY frame until it settles. At no point
      // may the existing content vanish or a spinner take its place.
      await tester.tap(find.byTooltip('Scan library folders'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.text('Alpha'),
          findsOneWidget,
          reason: 'the grid was blanked mid-refresh at frame $i',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'a refresh must not fall back to the first-load spinner '
              '(frame $i)',
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsOneWidget, reason: 'and it did refresh');
    });
  });
}
