import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AniLocalApp renders fetched series metadata', (tester) async {
    // coverImageRef is null so the test does no network image load.
    final series = Future.value(
      const Series(
        anilistId: 154587,
        titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
        format: 'TV',
        episodeCount: 28,
      ),
    );

    await tester.pumpWidget(AniLocalApp(seriesFuture: series));
    await tester.pumpAndSettle();

    expect(find.text('AniLocal'), findsOneWidget); // app bar
    expect(find.text('Frieren'), findsOneWidget); // display title
    // Metadata rows are Text.rich (label + value).
    expect(find.text('Format: TV', findRichText: true), findsOneWidget);
    expect(find.text('Episodes: 28', findRichText: true), findsOneWidget);
  });
}
