import 'dart:async';

import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/source_descriptor.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/domain/repositories/show_preferences_repository.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/library_services.dart';
import 'package:anilocal/ui/routes.dart';
import 'package:anilocal/ui/scan_control.dart';
import 'package:anilocal/ui/series_detail_screen.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:anilocal/ui/settings/sources_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_fix_match.dart';
import 'support/fake_library_repository.dart';
import 'support/fake_settings.dart';
import 'support/shell_harness.dart';

/// The detail page's FIRST FRAME.
///
/// The route is handed a complete [Series] — title, cover, meta — so none of
/// that should wait on the database. Only the episode list has to. These pin
/// that the hero paints while the episode query is still outstanding, and that
/// the page asks the data layer for as little as it can.

Series _series() => const Series(
  seriesId: 7,
  titles: Titles(romaji: 'Dragon Ball', native: 'ドラゴンボール'),
);

/// Episodes 1–3, with 1 and 2 watched — so "next" is unambiguously episode 3.
List<Episode> _episodes() => [
  for (var i = 1; i <= 3; i++)
    Episode(
      number: i,
      fileRef: '/tmp/ep$i.mkv',
      seriesId: 7,
      anchoredNumber: i,
      watched: i <= 2,
    ),
];

/// The show page's repository: three episodes on series 7 unless a test
/// supplies its own, with `upNextBySeries` pre-answered the way the real
/// repository would (furthest watched is 2, so next is anchor 3) — a test
/// checks the page's own derivation against it.
FakeLibraryRepository _repo({
  Completer<List<Episode>>? episodesCompleter,
  List<Episode>? episodes,
}) => FakeLibraryRepository(
  series: [_series()],
  episodes: {7: episodes ?? _episodes()},
  episodesCompleter: episodesCompleter,
  upNext: {7: _episodes()[2]},
);

Widget _app(FakeLibraryRepository repo) {
  final h = ShellHarness();
  return h.app(
    home: SeriesDetailScreen(
      series: _series(),
      services: _services(repo, metadata: [], skip: []),
      header: const HeaderHooks(
        onScan: _noScan,
        onUnmatched: _noop,
        unmatchedCount: 0,
      ),
    ),
  );
}

Future<void> _noScan() async {}
void _noop() {}

/// The services bundle a show-page test needs: the one fake repo behind every
/// interface, a real (idle) playback controller, and a settings bundle with
/// whatever source lists the test wants the ⚙ window to show.
LibraryServices _services(
  FakeLibraryRepository repo, {
  List<SourceDescriptor> metadata = const [],
  List<SourceDescriptor> skip = const [],
}) => LibraryServices(
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
  settingsActions: SettingsActions(
    sources: SourcesActions(
      repository: repo,
      onAddFolder: () async => (added: false, deniedLabel: null),
      onOpenAccessSettings: () async => false,
      scanning: ValueNotifier<bool>(false),
    ),
    metadataSources: metadata,
    skipSources: skip,
    onRefreshMetadata: () async =>
        const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
    scanning: ValueNotifier<bool>(false),
  ),
);

class _NoPrefs extends Fake implements ShowPreferencesRepository {}

void main() {
  _settingsFromShowPageTests();
  testWidgets('the hero paints on the FIRST frame, while the episode query is '
      'still outstanding', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // episodesFor never completes during this test: the DB is "still thinking".
    final pending = Completer<List<Episode>>();
    addTearDown(() => pending.complete(const []));
    await tester.pumpWidget(_app(_repo(episodesCompleter: pending)));
    await tester.pump();

    expect(
      find.text('Dragon Ball'),
      findsWidgets,
      reason:
          'the title comes from the Series the route was handed — it must '
          'not wait on the database',
    );
    expect(find.text('ドラゴンボール'), findsWidgets);
    // …and the episode list is honestly still loading.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('the page does NOT rebuild the whole library to find its own '
      'next episode', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _repo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      isNot(contains('upNextBySeries')),
      reason:
          'upNextBySeries rebuilds every series logical-episode map to read '
          'one entry; next-episode is derivable from the list already loaded',
    );
  });

  testWidgets('the derived next episode matches what upNextBySeries would have '
      'returned', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _repo();
    // The old query's answer for this series, computed by the real repository
    // semantics: furthest watched is 2, so next is the episode at anchor 3.
    final expected = (await repo.upNextBySeries())[7]!;
    repo.calls.clear();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(SeriesDetailScreen));
    final derived = (state as dynamic).debugNextEpisode as Episode?;
    expect(derived, isNotNull);
    expect(derived!.anchoredNumber, expected.anchoredNumber);
    expect(derived.number, expected.number);
    expect(derived.watched, isFalse);
  });

  group('the derivation matches upNextBySeries across its branches', () {
    // upNextBySeries: furthest WATCHED anchor -> the episode at anchor+1, shown
    // only if it exists and is unwatched. These drive each branch of that rule
    // through the real screen.
    Future<Episode?> derived(WidgetTester tester, List<Episode> eps) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(_repo(episodes: eps)));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(SeriesDetailScreen));
      return (state as dynamic).debugNextEpisode as Episode?;
    }

    Episode ep(int n, {bool watched = false}) => Episode(
      number: n,
      fileRef: '/tmp/ep$n.mkv',
      seriesId: 7,
      anchoredNumber: n,
      watched: watched,
    );

    testWidgets('nothing watched -> no next (a series never started)', (
      tester,
    ) async {
      expect(await derived(tester, [ep(1), ep(2), ep(3)]), isNull);
    });

    testWidgets('caught up -> no next', (tester) async {
      final all = [ep(1, watched: true), ep(2, watched: true)];
      expect(await derived(tester, all), isNull);
    });

    testWidgets('resolves from the FURTHEST watched, not the first gap', (
      tester,
    ) async {
      // Watched 1 and 3 (2 skipped): furthest is 3, so next is 4 — NOT 2.
      final eps = [ep(1, watched: true), ep(2), ep(3, watched: true), ep(4)];
      final next = await derived(tester, eps);
      expect(next?.anchoredNumber, 4);
    });

    testWidgets('no episode after the furthest watched -> no next', (
      tester,
    ) async {
      expect(await derived(tester, [ep(1), ep(2, watched: true)]), isNull);
    });
  });
}

void _settingsFromShowPageTests() {
  testWidgets('Settings opened FROM the show page lists the sources', (
    tester,
  ) async {
    // The show page built its own SettingsDialogActions and left the two
    // source lists at their empty defaults, so Metadata and Skip rendered
    // EMPTY from two of the window's three entry points. This drives the real
    // shell header (the ⚙ lives there), opens Settings from the show page, and
    // looks for a source by name.
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _repo();
    final shell = ShellHarness();
    await tester.pumpWidget(
      shell.app(
        home: SeriesDetailScreen(
          series: _series(),
          services: _services(
            repo,
            metadata: [
              SourceDescriptor(token: 'kitsu', displayName: 'Kitsu Probe'),
            ],
            skip: [
              SourceDescriptor(
                token: 'chapters',
                displayName: 'Chapters Probe',
              ),
            ],
          ),
          header: const HeaderHooks(
            onScan: _noScan,
            onUnmatched: _noop,
            unmatchedCount: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metadata'));
    await tester.pumpAndSettle();
    expect(
      find.text('Kitsu Probe'),
      findsOneWidget,
      reason: 'metadata list populated',
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chapters Probe'),
      findsOneWidget,
      reason: 'skip list populated',
    );
  });
}
