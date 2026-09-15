import 'package:anilocal/domain/models/cache_errors.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/source_descriptor.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';
import 'support/finders.dart';

/// `AniLocalApp` assembled end to end over in-memory fakes: the library
/// renders what the repository holds, the settings window reached from the
/// show page shows the shipped sources, and a cache the app cannot open
/// renders a message rather than spinning forever.

const _frieren = Series(
  seriesId: 154587,
  titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
  format: 'TV',
  episodeCount: 28,
);

/// The whole app over one fake repository, with everything else inert. The
/// SAME instance fills every repository slot, as the composition root does.
Widget _app(
  FakeLibraryRepository repo, {
  List<SourceDescriptor> metadataSources = const [],
  List<SourceDescriptor> skipSources = const [],
}) => AniLocalApp(
  repository: repo,
  fixMatch: const FakeFixMatch(),
  watchState: repo,
  sourceSelection: repo,
  watchOrder: repo,
  playback: PlaybackController(resolver: repo),
  missing: repo,
  showPreferences: repo,
  settings: const FakeSettings(),
  onScan: (_, {onProgress, cancellation}) async => const SyncSummary(
    filesScanned: 0,
    unchanged: 0,
    processed: 0,
    removed: 0,
    matched: 0,
    unmatched: 0,
    errored: 0,
    lookupsBySource: {},
  ),
  onRefreshMetadata: () async =>
      const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
  onAddFolder: () async => (added: false, deniedLabel: null),
  accessIssues: ValueNotifier<List<String>>(const []),
  missingFolders: ValueNotifier<List<String>>(const []),
  missingFolderPaths: ValueNotifier<Set<String>>(const {}),
  onOpenAccessSettings: () async => true,
  metadataSources: metadataSources,
  skipSources: skipSources,
);

void main() {
  group('app shell', () {
    _errorPanelTests();
    _settingsWiringTests();
    testWidgets('library renders cached series from the repository', (
      tester,
    ) async {
      await tester.pumpWidget(_app(FakeLibraryRepository(series: [_frieren])));
      // Bounded pumps, not pumpAndSettle: the header VFD readout may run a
      // continuous marquee (which never settles). Two pumps resolve the futures
      // and render the grid.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HeaderReadout), findsOneWidget);
      expect(find.text('Frieren'), findsOneWidget);
      expect(find.textContaining('TV'), findsOneWidget);
    });
  });
}

/// Settings opened from the SHOW PAGE lists the shipped sources.
///
/// The shipped bug was upstream of the show page: it assembled its own
/// settings bundle and the library screen did not forward the source lists.
/// So this drives the real wiring — `AniLocalApp` → library grid → card tap →
/// show page → header ⚙ → Metadata — rather than constructing the show page
/// with the lists already in hand, which would pass whatever the wiring did.
void _settingsWiringTests() {
  testWidgets('Settings from the show page shows the sources the app ships', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        FakeLibraryRepository(series: [_frieren]),
        metadataSources: const [
          SourceDescriptor(token: 'kitsu', displayName: 'Kitsu Probe'),
        ],
        skipSources: const [
          SourceDescriptor(token: 'chapters', displayName: 'Chapters Probe'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Frieren'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Metadata'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kitsu Probe'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Chapters Probe'), findsOneWidget);
  });
}

/// The library repository failing to open — corrupt file, read-only support
/// folder, or a cache from a newer build. Used to be an eternal spinner.
class _ThrowingRepository extends FakeLibraryRepository {
  @override
  Future<List<Series>> allSeries() async =>
      throw const CacheNewerThanAppException(20, 19);
}

void _errorPanelTests() {
  testWidgets('a cache from a newer build renders a message, not a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_ThrowingRepository()));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('newer version of AniLocal'),
      findsOneWidget,
      reason: 'the one open-failure with a specific remedy names it',
    );
    expect(
      findXpLabel('Copy diagnostics'),
      findsOneWidget,
    ); // XpButton uppercases
  });
}
