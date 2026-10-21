import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

/// The one yes/no dialog. What matters is the contract its callers rely on:
/// only the confirm button says yes, and every other way out says no — so a
/// caller can write `if (!await confirmAction(...)) return;` and be right.

class _Answer {
  bool? value;
}

Future<_Answer> _ask(WidgetTester tester) async {
  final answer = _Answer();
  await tester.pumpWidget(
    MaterialApp(
      theme: XpTheme.data(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer.value = await confirmAction(
              context,
              title: 'Remove this folder?',
              body: 'Its files leave the library.',
              confirmLabel: 'Remove folder',
              cancelLabel: 'Keep it',
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ask'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  group('confirmAction', () {
    testWidgets('shows the title, the body and both labels', (tester) async {
      await _ask(tester);
      expect(findXpLabel('Remove this folder?'), findsOneWidget);
      expect(find.text('Its files leave the library.'), findsOneWidget);
      expect(findXpLabel('Remove folder'), findsOneWidget);
      expect(findXpLabel('Keep it'), findsOneWidget);
    });

    testWidgets('the confirm button is the ONLY yes', (tester) async {
      final answer = await _ask(tester);
      await tester.tap(findXpLabel('Remove folder'));
      await tester.pumpAndSettle();
      expect(answer.value, isTrue);
      expect(findXpLabel('Remove folder'), findsNothing, reason: 'closed');
    });

    testWidgets('cancel answers no', (tester) async {
      final answer = await _ask(tester);
      await tester.tap(findXpLabel('Keep it'));
      await tester.pumpAndSettle();
      expect(answer.value, isFalse);
    });

    testWidgets('Escape answers no', (tester) async {
      final answer = await _ask(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(answer.value, isFalse);
    });

    testWidgets('a click on the barrier answers no', (tester) async {
      final answer = await _ask(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(answer.value, isFalse);
    });
  });
}
