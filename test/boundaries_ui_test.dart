import 'dart:async';

import 'package:anilocal/domain/models/folder_refused.dart';
import 'package:anilocal/domain/models/library_snapshot.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:anilocal/ui/app.dart';
import 'package:anilocal/ui/library_screen.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/widgets/header_actions.dart';
import 'package:anilocal/ui/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
);

/// A cache that cannot be opened.
class _BrokenRepository extends FakeLibraryRepository {
  @override
  Future<LibrarySnapshot> snapshot() async =>
      throw StateError('file is not a database');
}

Widget _app(
  FakeLibraryRepository repo, {
  Future<({bool added, String? deniedLabel})> Function()? onAddFolder,
  String? cachePath,
  Future<String> Function()? onResetCache,
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
  onScan: (_, {onProgress, cancellation}) async => _emptySummary,
  onRefreshMetadata: () async =>
      const RefreshSummary(seriesRefreshed: 0, skipsFetched: 0),
  onAddFolder: onAddFolder ?? () async => (added: false, deniedLabel: null),
  accessIssues: ValueNotifier<List<String>>(const []),
  missingFolders: ValueNotifier<List<String>>(const []),
  missingFolderPaths: ValueNotifier<Set<String>>(const {}),
  categoryLabelOf: (_) => null,
  onOpenAccessSettings: () async => true,
  cachePath: cachePath,
  onResetCache: onResetCache,
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The boundaries a user meets from the UI side: quitting, a folder the
/// library refuses, a cache that cannot open, a scan with nothing to scan,
/// and the sentences that tell an unplugged drive from a denied folder.
void main() {
  group('quit hooks', () {
    Future<void> sendQuitRequested() => TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          'anilocal/window',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('quitRequested'),
          ),
          (_) {},
        );

    testWidgets('the runner\'s quitRequested runs every hook and waits', (
      tester,
    ) async {
      WindowChrome.ensureInitialized();
      final ran = <String>[];
      final slow = Completer<void>();
      final removeA = WindowChrome.addQuitHook(() async => ran.add('a'));
      final removeB = WindowChrome.addQuitHook(() async {
        await slow.future;
        ran.add('b');
      });
      final removeC = WindowChrome.addQuitHook(
        () async => throw StateError('boom'),
      );
      addTearDown(() {
        removeA();
        removeB();
        removeC();
      });
      var replied = false;
      unawaited(sendQuitRequested().then((_) => replied = true));
      await tester.pump();
      expect(ran, ['a']);
      expect(replied, isFalse, reason: 'waits for the slow hook');
      slow.complete();
      await tester.pump();
      await tester.pump();
      expect(ran, ['a', 'b']);
      expect(replied, isTrue, reason: 'a throwing hook does not block');
    });

    testWidgets('a hook that hangs is cut off at the budget', (tester) async {
      WindowChrome.ensureInitialized();
      final remove = WindowChrome.addQuitHook(() => Completer<void>().future);
      addTearDown(remove);
      var replied = false;
      unawaited(sendQuitRequested().then((_) => replied = true));
      await tester.pump(
        WindowChrome.quitHookBudget - const Duration(seconds: 1),
      );
      expect(replied, isFalse);
      await tester.pump(const Duration(seconds: 1, milliseconds: 10));
      expect(replied, isTrue, reason: 'Cmd-Q can never hang on Dart');
    });

    testWidgets('a removed hook does not run', (tester) async {
      WindowChrome.ensureInitialized();
      var ran = 0;
      WindowChrome.addQuitHook(() async => ran++)();
      await sendQuitRequested();
      await tester.pump();
      expect(ran, 0);
    });
  });

  group('the Scan tab', () {
    var scans = 0;
    Widget bar({required bool canScan}) => MaterialApp(
      theme: XpTheme.data(),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          child: HeaderActionsBar(
            scanning: false,
            unmatchedCount: 0,
            onScan: () async => scans++,
            onUnmatched: () {},
            onSettings: () {},
            canScan: canScan,
          ),
        ),
      ),
    );

    testWidgets('is disabled, and says why, when there is nothing to scan', (
      tester,
    ) async {
      await tester.pumpWidget(bar(canScan: false));
      expect(find.byTooltip('Scan library folders'), findsNothing);
      expect(
        find.byTooltip('Add a folder first (Settings › Folders)'),
        findsOneWidget,
      );
      await tester.tap(findXpLabel('Scan'));
      await tester.pump();
      expect(scans, 0, reason: 'disabled, not merely relabelled');
      await tester.pumpWidget(bar(canScan: true));
      expect(find.byTooltip('Scan library folders'), findsOneWidget);
      await tester.tap(findXpLabel('Scan'));
      await tester.pump();
      expect(scans, 1);
    });
  });

  group('copy', () {
    test(
      'the unreadable line tells an unplugged drive from a denied folder',
      () {
        expect(
          unreadableFoldersText(
            ['/Volumes/NAS/anime'],
            missing: {'/Volumes/NAS/anime'},
          ),
          allOf(
            contains('not connected'),
            contains('reconnect'),
            isNot(contains('re-add')),
          ),
        );
        expect(
          unreadableFoldersText(['/Users/me/Downloads/anime'], missing: {}),
          allOf(contains("couldn't read"), contains('re-add')),
        );
        expect(
          unreadableFoldersText(['/a', '/b'], missing: {'/a'}),
          allOf(contains('/a is not connected'), contains("couldn't read /b")),
        );
      },
    );

    test('the scan summary names sources that were down', () {
      const s = SyncSummary(
        filesScanned: 3,
        unchanged: 0,
        processed: 3,
        removed: 0,
        matched: 3,
        unmatched: 0,
        errored: 0,
        lookupsBySource: {'kitsu': 3},
        skipLookupsFailed: 2,
        sourcesDown: ['anilist'],
      );
      final text = scanSummaryText(s, (t) => t.toUpperCase());
      expect(text, contains('2 skip lookups failed, will retry'));
      expect(text, contains('unreachable: ANILIST'));
      expect(
        scanSummaryText(_emptySummary, (t) => t),
        isNot(contains('unreachable')),
      );
    });
  });

  group('the library screen', () {
    testWidgets('a refused folder is a sentence, not a dropped future', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(
        _app(
          FakeLibraryRepository(),
          onAddFolder: () async =>
              throw const FolderRefused('/a/b is already in your library.'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(findXpLabel('Add your first folder'));
      await tester.pumpAndSettle();
      expect(find.text('/a/b is already in your library.'), findsOneWidget);
    });

    testWidgets('a broken cache names its file and offers a reset', (
      tester,
    ) async {
      _wide(tester);
      var resets = 0;
      await tester.pumpWidget(
        _app(
          _BrokenRepository(),
          cachePath: '/Library/Application Support/anilocal/cache.sqlite',
          onResetCache: () async {
            resets++;
            return '/Library/Application Support/anilocal/cache.sqlite.broken-1';
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open the library cache."), findsOneWidget);
      expect(
        find.textContaining('file is not a database'),
        findsNothing,
        reason: 'the raw exception never reaches the user',
      );
      expect(
        find.textContaining('/anilocal/cache.sqlite'),
        findsOneWidget,
        reason: 'the file is named',
      );
      await tester.tap(findXpLabel('Reset library cache'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(find.textContaining('cache.sqlite.broken-1'), findsOneWidget);
      expect(findXpLabel('Quit AniLocal'), findsOneWidget);
      expect(
        findXpLabel('Reset library cache'),
        findsNothing,
        reason: 'one reset per broken cache',
      );
    });

    testWidgets('a pending card says "Identifying…" only while a scan runs', (
      tester,
    ) async {
      _wide(tester);
      const pending = Series(
        seriesId: -42,
        titles: Titles(romaji: 'Mystery Show'),
        pending: true,
      );
      final scanStarted = Completer<void>();
      final scanDone = Completer<SyncSummary>();
      final repo = FakeLibraryRepository(series: [pending], folders: ['/a']);
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
          onScan: (_, {onProgress, cancellation}) {
            scanStarted.complete();
            return scanDone.future;
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
      expect(find.text('Not identified yet — scan to retry'), findsOneWidget);
      expect(find.text('Identifying…'), findsNothing);

      await tester.tap(find.byTooltip('Scan library folders'));
      await tester.pump();
      await scanStarted.future;
      await tester.pump();
      expect(find.text('Identifying…'), findsOneWidget);

      scanDone.complete(_emptySummary);
      await tester.pumpAndSettle();
      expect(find.text('Not identified yet — scan to retry'), findsOneWidget);
    });

    testWidgets('with no folders the header\'s Scan is disabled', (
      tester,
    ) async {
      _wide(tester);
      await tester.pumpWidget(_app(FakeLibraryRepository()));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Add a folder first (Settings › Folders)'),
        findsOneWidget,
      );
      // A fresh app (the shell's services bind to the first repository).
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: _app(FakeLibraryRepository(folders: ['/a'])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scan library folders'), findsOneWidget);
    });
  });
}
