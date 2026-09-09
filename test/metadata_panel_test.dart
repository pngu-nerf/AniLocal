import 'package:anilocal/data/metadata/metadata_provider.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/metadata_source.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/source_preference.dart';
import 'package:anilocal/ui/settings/panels/metadata_panel.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_settings.dart';

/// Records what the panel persisted, so a test can assert on it.
class _Recorder extends FakeSettings {
  _Recorder([this.stored = const [], this.clientIds = const {}]);
  List<SourcePreference> stored;
  Map<String, String?> clientIds;

  @override
  Future<List<SourcePreference>> loadMetadataSourceOrder() async => stored;
  @override
  Future<void> setMetadataSourceOrder(List<SourcePreference> order) async =>
      stored = order;

  @override
  Future<String?> loadSourceClientId(String token) async => clientIds[token];
  @override
  Future<void> setSourceClientId(String token, String? clientId) async =>
      clientIds = {...clientIds, token: clientId};
}

class _StubProvider implements MetadataProvider {
  _StubProvider(this.token);
  @override
  final String token;
  @override
  String get displayName => token;
  @override
  String get idNamespace => token;
  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;
  @override
  Future<bool> isConfigured() async => true;
  @override
  bool get isFallbackOnly => false;
  int calls = 0;
  @override
  Future<List<Series>> searchCandidates(String t, {int perPage = 10}) async {
    calls++;
    return const [];
  }

  @override
  Future<List<Series>> fetchByProviderIds(List<int> ids) async => const [];
}

Future<void> _pump(WidgetTester tester, _Recorder settings) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: XpTheme.data(),
      home: Scaffold(
        body: MetadataPanel(
          settings: settings,
          sources: const [
            MetadataSource(token: 'anilist', displayName: 'AniList'),
            MetadataSource(token: 'kitsu', displayName: 'Kitsu'),
            MetadataSource(
              token: 'myanimelist',
              displayName: 'MyAnimeList',
              requiresClientId: true,
              setupHint:
                  'Needs a free client ID from your own MyAnimeList '
                  'account',
              setupUrl: 'https://myanimelist.net/apiconfig',
              setupInstructions:
                  'Any MyAnimeList account can create one: Profile settings '
                  '→ API → Create ID.',
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every source, including one awaiting setup', (
    tester,
  ) async {
    await _pump(tester, _Recorder());

    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('Kitsu'), findsOneWidget);
    // Hiding an unconfigured source would leave no way to discover it.
    expect(find.text('MyAnimeList'), findsOneWidget);
    expect(
      find.textContaining('free client ID from your own'),
      findsOneWidget,
      reason: 'the row must say it is a personal key, not a developer artifact',
    );
  });

  testWidgets('the first row is captioned as the source of truth', (
    tester,
  ) async {
    await _pump(tester, _Recorder());

    expect(find.text('Source of truth'), findsOneWidget);
  });

  testWidgets('a source awaiting setup cannot be switched on', (tester) async {
    await _pump(tester, _Recorder());

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.length, 3);
    // The unconfigured one is last in built-in order and has no handler.
    expect(boxes.last.onChanged, isNull);
    expect(boxes.first.onChanged, isNotNull);
  });

  testWidgets('turning a source off persists it', (tester) async {
    final settings = _Recorder();
    await _pump(tester, settings);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(
      settings.stored.firstWhere((p) => p.token == 'anilist').enabled,
      isFalse,
    );
    expect(
      settings.stored.firstWhere((p) => p.token == 'kitsu').enabled,
      isTrue,
      reason: 'toggling one source must not disturb the others',
    );
  });

  testWidgets('a source needing a key offers one, and says so', (tester) async {
    await _pump(tester, _Recorder());

    expect(find.textContaining('free client ID from your own'), findsOneWidget);
    expect(find.text('ADD KEY'), findsOneWidget);
    // Sources that need nothing must not grow a button.
    expect(find.text('CHANGE'), findsNothing);
  });

  testWidgets('once a key is stored the source becomes usable', (tester) async {
    await _pump(tester, _Recorder(const [], const {'myanimelist': 'abc123'}));

    // The affordance flips to Change, the setup hint is gone, and the row can
    // now be switched on — all derived from the STORED KEY, not a snapshot.
    expect(find.text('CHANGE'), findsOneWidget);
    expect(find.textContaining('free client ID from your own'), findsNothing);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.last.onChanged, isNotNull);
  });

  testWidgets('a saved order is reflected in the list', (tester) async {
    await _pump(
      tester,
      _Recorder(const [
        SourcePreference(token: 'kitsu'),
        SourcePreference(token: 'anilist'),
      ]),
    );

    // Kitsu is now first, so it carries the source-of-truth caption.
    final kitsu = tester.getTopLeft(find.text('Kitsu'));
    final anilist = tester.getTopLeft(find.text('AniList'));
    expect(kitsu.dy, lessThan(anilist.dy));
  });

  test(
    'the saved order actually changes which source is asked first',
    () async {
      // The UI half is only worth anything if the chain honours it.
      final anilist = _StubProvider('anilist');
      final kitsu = _StubProvider('kitsu');
      final settings = _Recorder(const [
        SourcePreference(token: 'kitsu'),
        SourcePreference(token: 'anilist', enabled: false),
      ]);

      await SeriesMatcher(
        providers: [anilist, kitsu],
        loadOrder: settings.loadMetadataSourceOrder,
      ).match('Cowboy Bebop');

      expect(kitsu.calls, greaterThan(0));
      expect(anilist.calls, 0, reason: 'disabled sources are never asked');
    },
  );

  test('reordering takes effect without rebuilding the matcher', () async {
    // loadOrder is read per match, not snapshotted at construction — the
    // settings window can reorder while the app is open.
    final anilist = _StubProvider('anilist');
    final kitsu = _StubProvider('kitsu');
    final settings = _Recorder();
    final matcher = SeriesMatcher(
      providers: [anilist, kitsu],
      loadOrder: settings.loadMetadataSourceOrder,
    );

    await matcher.match('x');
    expect(anilist.calls, 1, reason: 'built-in order first');

    await settings.setMetadataSourceOrder(const [
      SourcePreference(token: 'anilist', enabled: false),
      SourcePreference(token: 'kitsu'),
    ]);
    await matcher.match('y');

    expect(anilist.calls, 1, reason: 'now disabled — not asked again');
    expect(kitsu.calls, greaterThan(0));
  });
}
