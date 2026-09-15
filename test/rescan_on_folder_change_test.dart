import 'dart:ui' show Size;

import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';
import 'support/finders.dart';

const _emptySummary = SyncSummary(
  filesScanned: 0,
  unchanged: 0,
  processed: 0,
  removed: 0,
  matched: 0,
  unmatched: 0,
  errored: 0,
  lookupsBySource: {},
);

void main() {
  group('rescan on folder change', () {
    testWidgets('rescan fires only when the folder set actually changed', (
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
      final repo = FakeLibraryRepository(folders: ['/a']);
      var scans = 0;

      await tester.pumpWidget(
        AniLocalApp(
          repository: repo,
          fixMatch: const FakeFixMatch(),
          watchState: repo,
          sourceSelection: repo,
          watchOrder: repo,
          playback: PlaybackController(resolver: repo),
          missing: repo,
          showPreferences: repo,
          settings: const FakeSettings(),
          onScan: (_, {onProgress, cancellation}) async {
            scans++;
            return _emptySummary;
          },
          onRefreshMetadata: () async =>
              const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
          onAddFolder: () async => (added: false, deniedLabel: null),
          accessIssues: ValueNotifier<List<String>>(const []),
          missingFolders: ValueNotifier<List<String>>(const []),
          missingFolderPaths: ValueNotifier<Set<String>>(const {}),
          onOpenAccessSettings: () async => true,
        ),
      );
      await tester.pumpAndSettle();

      // Sources is a tab in the settings window now, not a pushed page and no
      // longer a header action of its own: ⚙ opens the window, which lands on
      // Sources, and Done closes it. The DECISION under test is unchanged:
      // rescan only when the folder SET moved.

      // 1) Open settings and close it WITHOUT changing the set.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Folders'), findsWidgets, reason: 'lands on the tab');
      await tester.tap(findXpLabel('Done'));
      await tester.pumpAndSettle();
      expect(scans, 0, reason: 'no-op dismissal must not scan');

      // 2) Open it, change the set (simulate an add), then close.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      repo.folders = ['/a', '/b'];
      await tester.tap(findXpLabel('Done'));
      await tester.pumpAndSettle();
      expect(scans, 1, reason: 'a changed folder set triggers one rescan');
    });
  });
}
