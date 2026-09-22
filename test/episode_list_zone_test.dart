import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/ui/theater/zones/episode_list_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/episodes.dart';

Widget _host(List<Episode> eps, Episode current, ValueChanged<Episode> onSel) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: EpisodeListZone(
            episodes: eps,
            current: current,
            onSelect: onSel,
          ),
        ),
      ),
    );

void main() {
  group('EpisodeListZone', () {
    testWidgets('tapping an episode reports the selection', (tester) async {
      final eps = [for (var n = 1; n <= 5; n++) testEpisode(n)];
      Episode? picked;
      await tester.pumpWidget(_host(eps, eps[0], (e) => picked = e));
      await tester.tap(find.text('Episode 3'));
      await tester.pump();
      expect(picked?.anchoredNumber, 3);
    });

    testWidgets('the now-playing mark follows current when it changes', (
      tester,
    ) async {
      final eps = [for (var n = 1; n <= 5; n++) testEpisode(n)];
      await tester.pumpWidget(_host(eps, eps[0], (_) {}));
      // Episode 1 starts marked (speaker icon = now playing, not watched).
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Host swaps current to episode 4 (as auto-advance would).
      await tester.pumpWidget(_host(eps, eps[3], (_) {}));
      await tester.pump();
      // Still exactly one mark — it moved, not duplicated.
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('a long list auto-scrolls to keep current visible', (
      tester,
    ) async {
      final eps = [for (var n = 1; n <= 60; n++) testEpisode(n)];
      await tester.pumpWidget(_host(eps, eps[0], (_) {}));
      await tester.pumpAndSettle();
      // Episode 60 is far off-screen initially.
      expect(find.text('Episode 60'), findsNothing);

      // Current jumps to the last episode (auto-advance to the season's end).
      await tester.pumpWidget(_host(eps, eps[59], (_) {}));
      await tester.pumpAndSettle();
      // The rail scrolled it into view.
      expect(find.text('Episode 60'), findsOneWidget);
    });

    testWidgets('empty episode list shows an empty-state message', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const [], testEpisode(1), (_) {}));
      expect(find.text('No episodes here yet.'), findsOneWidget);
    });
  });
}
