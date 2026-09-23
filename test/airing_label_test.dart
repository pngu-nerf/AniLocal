import 'package:anilocal/domain/airing.dart';
import 'package:anilocal/ui/theme/xp_tokens.dart';
import 'package:anilocal/ui/widgets/airing_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The indicator's words are measured against the clock when drawn, so the
/// tests fix both the instant and "now".
void main() {
  final now = DateTime(2026, 9, 23, 20);

  group('relativeAirTime', () {
    test('hours under two days, days after; "now" inside the hour', () {
      expect(relativeAirTime(now.add(const Duration(minutes: 30)), now), 'now');
      expect(relativeAirTime(now.add(const Duration(hours: 5)), now), 'in 5h');
      expect(
        relativeAirTime(now.add(const Duration(hours: 47)), now),
        'in 47h',
      );
      expect(relativeAirTime(now.add(const Duration(days: 3)), now), 'in 3d');
      expect(
        relativeAirTime(now.subtract(const Duration(hours: 2)), now),
        '2h ago',
      );
      expect(
        relativeAirTime(now.subtract(const Duration(days: 4)), now),
        '4d ago',
      );
    });
  });

  Future<void> pump(WidgetTester tester, AiringState state) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text.rich(
              TextSpan(
                children: AiringLabel.spans(state, now: now, fontSize: 12),
              ),
            ),
          ),
        ),
      );

  // The inner Text.rich (icon span + words) — WidgetSpans render as an
  // object-replacement character in the plain text, so match by containment.
  Finder line(String text) => find.byWidgetPredicate(
    (w) => w is Text && (w.textSpan?.toPlainText().contains(text) ?? false),
  );
  Color colourOf(WidgetTester tester, String text) =>
      (tester.widget<Text>(line(text).last).textSpan! as TextSpan)
          .style!
          .color!;

  testWidgets(
    'caught up: the dim note with the next episode and its distance',
    (tester) async {
      await pump(
        tester,
        Airing(nextEpisode: 9, nextAt: now.add(const Duration(days: 3))),
      );
      expect(line('Ep 9 · in 3d').last, findsOneWidget);
      expect(colourOf(tester, 'Ep 9 · in 3d'), Xp.textDim);
      expect(find.byIcon(Icons.podcasts), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Airing — episode 9 on Sat 26 Sep, 20:00',
      );
    },
  );

  testWidgets('an aired episode not in the library: the amber flag', (
    tester,
  ) async {
    await pump(
      tester,
      NewEpisode(8, airedAt: now.subtract(const Duration(days: 2))),
    );
    expect(line('Ep 8 out').last, findsOneWidget);
    expect(colourOf(tester, 'Ep 8 out'), Xp.warning);
    expect(find.byIcon(Icons.new_releases_outlined), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Episode 8 aired 2d ago (Mon 21 Sep, 20:00) — not in your library yet',
    );
  });

  testWidgets('no schedule (a fallback source): just "Airing"', (tester) async {
    await pump(tester, const Airing());
    expect(line('Airing').last, findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Airing — the next episode is not scheduled yet',
    );
  });

  testWidgets('a finale date reads as a day, no time', (tester) async {
    await pump(tester, NewEpisode(12, airedAt: DateTime(2026, 9, 20)));
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Episode 12 aired 3d ago (Sun 20 Sep) — not in your library yet',
    );
  });
}
