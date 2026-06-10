import 'package:anilocal/domain/models/identified_episode.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AniLocalApp renders scan results with a summary', (
    tester,
  ) async {
    final results = Future.value(const [
      IdentifiedEpisode(
        filePath: '/lib/Frieren - 01.mkv',
        parsedTitle: 'Frieren',
        parsedEpisodeNumber: 1,
        series: Series(
          anilistId: 154587,
          titles: Titles(romaji: 'Sousou no Frieren', english: 'Frieren'),
        ),
        matchScore: 0.95,
      ),
      IdentifiedEpisode(filePath: '/lib/mystery.mkv', parsedTitle: 'mystery'),
    ]);

    await tester.pumpWidget(AniLocalApp(resultsFuture: results));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 files'), findsOneWidget);
    expect(find.textContaining('1 matched'), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget); // matched title (english)
    expect(find.text('— no match —'), findsOneWidget); // unmatched row
  });
}
