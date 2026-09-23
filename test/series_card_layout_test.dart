import 'package:anilocal/domain/airing.dart';
import 'package:anilocal/domain/missing_episodes.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/ui/library/series_card.dart';
import 'package:anilocal/ui/routes.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_library_repository.dart';
import 'support/library_services.dart';

Future<void> _noScan() async {}
void _noop() {}

/// The card's text band is a FIXED height (`kCardTextRegion`), fed to the grid
/// delegate so every cell is uniform; its one meta line has 15 px. Anything
/// composed into that line — the download tally, the airing indicator — must
/// not grow the line, or the card overflows by a pixel and paints a striped
/// bar under every show. That happened on the first real-font run of the
/// airing label: a nested text box inside a `WidgetSpan` takes the font's own
/// line metrics, not the line's `height: 1.2`, and middle-aligned it pushed
/// the line to 16 px.
///
/// Rendered with the BUNDLED Archivo, loaded for this file only (every other
/// test keeps Ahem — `test/goldens/visual_identity_test.dart` explains why):
/// the overflow is a real-font metric and Ahem does not reproduce it.
void main() {
  setUpAll(() async {
    await (FontLoader(
      'Archivo',
    )..addFont(rootBundle.load('fonts/Archivo-Variable.ttf'))).load();
  });

  final now = DateTime(2026, 9, 23, 20);
  const series = Series(
    seriesId: 1,
    titles: Titles(romaji: 'Sousou no Frieren'),
    format: 'TV',
    episodeCount: 28,
  );
  const tally = DownloadTally(inRange: 8, outOfRange: 0, total: 28);

  /// One card at exactly the cell the library grid computes for a tile of
  /// this width (`library_screen.dart`, `_gridDelegate`).
  Future<void> pumpCard(WidgetTester tester, AiringState? airing) async {
    const tileWidth = 195.0;
    final services = testLibraryServices(FakeLibraryRepository());
    await tester.pumpWidget(
      MaterialApp(
        theme: XpTheme.data(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: tileWidth,
              height: tileWidth / kPosterAspect + kCardTextRegion,
              child: SeriesCard(
                series: series,
                services: services,
                header: const HeaderHooks(onScan: _noScan, onUnmatched: _noop),
                nextEpisode: null,
                downloaded: tally,
                airing: airing,
                unavailable: false,
                onPlay: (_, _) async {},
                onReturn: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the card text band holds its meta line', () {
    testWidgets('type and tally alone', (tester) async {
      await pumpCard(tester, null);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the dim airing note', (tester) async {
      await pumpCard(
        tester,
        Airing(nextEpisode: 9, nextAt: now.add(const Duration(days: 3))),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ep 9 · in 3d'), findsOneWidget);
    });

    testWidgets('with the amber new-episode flag', (tester) async {
      await pumpCard(
        tester,
        NewEpisode(8, airedAt: now.subtract(const Duration(days: 2))),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ep 8 out'), findsOneWidget);
    });
  });
}
