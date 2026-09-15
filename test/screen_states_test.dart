import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/episode_source.dart';
import 'package:anilocal/domain/models/library_folder.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/source_preference.dart';
import 'package:anilocal/domain/models/sync_control.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/library_services.dart';
import 'package:anilocal/ui/licences_screen.dart';
import 'package:anilocal/ui/routes.dart';
import 'package:anilocal/ui/scan_control.dart';
import 'package:anilocal/ui/series_detail_screen.dart';
import 'package:anilocal/ui/settings/panels/source_list_panel.dart';
import 'package:anilocal/ui/settings/panels/sources_panel.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/sources_actions.dart';
import 'package:anilocal/ui/theater/zones/episode_list_zone.dart';
import 'package:anilocal/ui/theater/zones/series_info_zone.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';
import 'support/fake_sources.dart';
import 'support/finders.dart';
import 'support/shell_harness.dart';

/// Every screen in the states it did not handle. Each test here is a state
/// the audit found rendering something wrong — a spinner that never ended,
/// "No episodes" for a list still loading, a title for a show the library no
/// longer had, one banner for two different problems — pinned as the right
/// thing now.
const _show = Series(
  seriesId: 7,
  titles: Titles(romaji: 'Dragon Ball'),
  format: 'TV',
  episodeCount: 3,
);

class _NoPrefs extends Fake implements ShowPreferencesRepository {}

LibraryServices _services(
  FakeLibraryRepository repo, {
  ValueNotifier<Set<String>>? missing,
  ValueNotifier<List<String>>? denied,
  String? Function(String)? categoryLabelOf,
}) {
  final missingN = missing ?? ValueNotifier<Set<String>>(const {});
  final deniedN = denied ?? ValueNotifier<List<String>>(const []);
  final label = categoryLabelOf ?? (_) => null;
  return LibraryServices(
    repository: repo,
    fixMatch: const FakeFixMatch(),
    watchState: repo,
    sourceSelection: repo,
    watchOrder: repo,
    missingEpisodes: repo,
    showPreferences: _NoPrefs(),
    settings: const FakeSettings(),
    playback: PlaybackController(resolver: repo),
    scan: ScanControl(),
    missingFolderPaths: missingN,
    accessIssues: deniedN,
    categoryLabelOf: label,
    unmatchedCount: ValueNotifier<int>(0),
    settingsActions: SettingsActions(
      sources: SourcesActions(
        repository: repo,
        onAddFolder: () async => (added: false, deniedLabel: null),
        onOpenAccessSettings: () async => false,
        scanning: ValueNotifier<bool>(false),
        missingFolderPaths: missingN,
        accessIssues: deniedN,
        categoryLabelOf: label,
      ),
      metadataSources: const [],
      skipSources: const [],
      onRefreshMetadata: () async =>
          const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
      scanning: ValueNotifier<bool>(false),
    ),
  );
}

Future<void> _noScan() async {}
void _noop() {}

/// Settle a page that (a) probes the disk — real `File.exists` completes only
/// while the test runs real async, hence `runAsync` — and (b) drives a header
/// marquee that never settles, hence pumping by time rather than
/// `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  // The probe is one `exists()` per source, sequentially; each needs a turn
  // of the real event loop AND a microtask flush before the next is issued.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 1));
}

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the show page', () {
    testWidgets('a show that left the library says so, not the old title', (
      tester,
    ) async {
      _wide(tester);
      // The page was pushed with the show; by the time it reads, the
      // repository no longer has it (pruned, or re-identified away).
      final repo = FakeLibraryRepository(series: const [], episodes: const {});
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: SeriesDetailScreen(
            series: _show,
            services: _services(repo),
            header: const HeaderHooks(onScan: _noScan, onUnmatched: _noop),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.text('This show is no longer in your library.'),
        findsOneWidget,
      );
      expect(find.text('Dragon Ball'), findsNothing, reason: 'stale identity');
      expect(
        tester.widget<HeaderReadout>(find.byType(HeaderReadout)).title,
        'Not in library',
        reason: 'the old name would claim a page the library lacks',
      );
    });

    testWidgets('the title follows the repository, not the push-time value', (
      tester,
    ) async {
      _wide(tester);
      final repo = FakeLibraryRepository(
        series: [_show],
        episodes: {7: _plainEpisodes()},
      );
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: SeriesDetailScreen(
            series: _show,
            services: _services(repo),
            header: const HeaderHooks(onScan: _noScan, onUnmatched: _noop),
          ),
        ),
      );
      await _settle(tester);
      expect(
        tester.widget<HeaderReadout>(find.byType(HeaderReadout)).title,
        'Dragon Ball',
      );
      // A reassign renamed the show underneath; the header's Scan reloads.
      repo.series = [
        const Series(seriesId: 7, titles: Titles(romaji: 'Dragon Ball Z')),
      ];
      await tester.tap(find.byTooltip('Scan library folders'));
      await _settle(tester);
      expect(
        tester.widget<HeaderReadout>(find.byType(HeaderReadout)).title,
        'Dragon Ball Z',
      );
    });

    testWidgets('the show page follows the scan: a reload per progress burst '
        'and one when it ends', (tester) async {
      _wide(tester);
      final repo = FakeLibraryRepository(
        series: [_show],
        episodes: {7: _plainEpisodes()},
      );
      final services = _services(repo);
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: SeriesDetailScreen(
            series: _show,
            services: services,
            header: const HeaderHooks(onScan: _noScan, onUnmatched: _noop),
          ),
        ),
      );
      await _settle(tester);
      int reads() => repo.calls.where((c) => c == 'episodesFor').length;
      final before = reads();

      // A scan starts and reports per title: three reports in one burst.
      services.scan.begin();
      for (var i = 1; i <= 3; i++) {
        services.scan.report(
          SyncProgress(done: i, total: 10, phase: 'identifying'),
        );
        await tester.pump();
      }
      expect(reads(), before, reason: 'debounced — not one read per report');
      await tester.pump(kScanReloadDebounce + const Duration(milliseconds: 50));
      await _settle(tester);
      expect(reads(), before + 1, reason: 'one reload for the burst');

      services.scan.end();
      await _settle(tester);
      expect(reads(), before + 2, reason: 'and one when the scan ends');
    });

    testWidgets('a missing drive and a denied folder get DIFFERENT banners, '
        'and the dimmed list is inert', (tester) async {
      _wide(tester);
      final missing = ValueNotifier<Set<String>>(const {});
      final denied = ValueNotifier<List<String>>(const []);
      final repo = FakeLibraryRepository(
        series: [_show],
        episodes: {7: _plainEpisodes(folder: '/Users/me/Downloads/Anime')},
      );
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: SeriesDetailScreen(
            series: _show,
            services: _services(
              repo,
              missing: missing,
              denied: denied,
              categoryLabelOf: (p) =>
                  p.startsWith('/Users/me/Downloads') ? 'Downloads' : null,
            ),
            header: const HeaderHooks(onScan: _noScan, onUnmatched: _noop),
          ),
        ),
      );
      await _settle(tester);
      // Files do not exist on this machine, so the probe alone says missing.
      expect(find.textContaining("drive isn't connected"), findsOneWidget);
      expect(find.byType(SliverIgnorePointer), findsOneWidget);
      expect(
        tester
            .widget<SliverIgnorePointer>(find.byType(SliverIgnorePointer))
            .ignoring,
        isTrue,
        reason: 'no menu may fire under a banner that says "reconnect"',
      );

      // The folder-health pass says the CATEGORY is denied: a different
      // problem, a different remedy — and it reaches the page live.
      denied.value = const ['Downloads'];
      await _settle(tester);
      expect(
        find.textContaining("can't read this show's folder"),
        findsOneWidget,
      );
      expect(find.textContaining("drive isn't connected"), findsNothing);
      expect(findXpLabel('Open Settings'), findsOneWidget);

      // Granted again: back to the probe's verdict.
      denied.value = const [];
      await _settle(tester);
      expect(
        find.textContaining("can't read this show's folder"),
        findsNothing,
      );
    });
  });

  group('the theater zones', () {
    testWidgets('the rail shows a spinner while loading, not "No episodes"', (
      tester,
    ) async {
      Widget rail(List<Episode>? eps) => MaterialApp(
        theme: XpTheme.data(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: EpisodeListZone(
              episodes: eps,
              current: _plainEpisodes().first,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(rail(null));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No episodes here yet.'), findsNothing);
      await tester.pumpWidget(rail(const []));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No episodes here yet.'), findsOneWidget);
    });

    testWidgets('the info zone shows no count until it knows one', (
      tester,
    ) async {
      const unknown = Series(seriesId: 1, titles: Titles(romaji: 'X'));
      Widget zone(int? count) => MaterialApp(
        theme: XpTheme.data(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: SeriesInfoZone(
              series: unknown,
              episodeCount: count,
              nowPlaying: _plainEpisodes().first,
            ),
          ),
        ),
      );
      await tester.pumpWidget(zone(null));
      expect(find.textContaining('episodes'), findsNothing);
      await tester.pumpWidget(zone(12));
      expect(find.textContaining('12 episodes'), findsOneWidget);
    });
  });

  group('settings panels', () {
    testWidgets(
      'Folders: a load failure is a message, not an eternal spinner',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: XpTheme.data(),
            home: Scaffold(
              body: SourcesPanel(
                sources: fakeSourcesActions(_ThrowingSources()),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.textContaining("Couldn't read the folder list"),
          findsOneWidget,
        );
      },
    );

    testWidgets('Folders: a row says when its drive is missing or its access '
        'denied', (tester) async {
      final missing = ValueNotifier<Set<String>>({'/lib/usb'});
      final denied = ValueNotifier<List<String>>(const ['Downloads']);
      await tester.pumpWidget(
        MaterialApp(
          theme: XpTheme.data(),
          home: Scaffold(
            body: SourcesPanel(
              sources: fakeSourcesActions(
                FakeSourcesRepository([
                  '/lib/usb',
                  '/Users/me/Downloads/A',
                  '/lib/ok',
                ]),
                missingFolderPaths: missing,
                accessIssues: denied,
                categoryLabelOf: (p) =>
                    p.startsWith('/Users/me/Downloads') ? 'Downloads' : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.textContaining('Access needed'), findsOneWidget);
      // The healthy folder says nothing extra.
      expect(find.textContaining('Not connected'), findsOneWidget);
      // Replugged: the row clears without a reload.
      missing.value = const {};
      await tester.pump();
      expect(find.text('Not connected'), findsNothing);
    });

    testWidgets('Metadata/Skip list: a load failure is a message', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: XpTheme.data(),
          home: Scaffold(
            body: SourceListPanel(
              sources: const [],
              settings: const FakeSettings(),
              loadOrder: () async => throw StateError('disk gone'),
              saveOrder: (List<SourcePreference> _) async {},
              caption: 'x',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining("Couldn't read the source list"),
        findsOneWidget,
      );
    });
  });

  group('the licences page', () {
    testWidgets('publishes a header spec like every other page', (
      tester,
    ) async {
      _wide(tester);
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => LicencesScreen.open(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<HeaderReadout>(find.byType(HeaderReadout)).title,
        'Licences',
        reason: 'the stock LicensePage left the header spinning',
      );
    });
  });
}

/// Episodes whose sources live under [folder] — the shape the show page's
/// folder-health verdict reads.
List<Episode> _plainEpisodes({String folder = '/lib/a'}) => [
  for (var i = 1; i <= 3; i++)
    Episode(
      number: i,
      fileRef: '$folder/ep$i.mkv',
      seriesId: 7,
      anchoredNumber: i,
      sources: [
        EpisodeSource(
          fileRef: '$folder/ep$i.mkv',
          folderPath: folder,
          folderSortOrder: 0,
        ),
      ],
    ),
];

class _ThrowingSources extends FakeSourcesRepository {
  @override
  Future<List<LibraryFolder>> watchedFolders() async =>
      throw StateError('database is locked');
}
