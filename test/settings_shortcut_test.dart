import 'dart:async';

import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:anilocal/ui/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// ⌘, (Ctrl+, elsewhere) and the menu bar's Settings… item open Settings for
/// the TOP page through the SAME callback its ⚙ fires — so each page's own
/// post-close behaviour runs — and fail ABSENT exactly where the ⚙ is absent.
/// Registered on the app-wide key handler, like Escape, so it works when
/// nothing is focused.

Future<void> _press(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

HeaderSpec _withSettings(VoidCallback onSettings) => HeaderSpec(
  title: 'Library',
  actions: AppActions(
    scanning: false,
    unmatchedCount: 0,
    onScan: () async {},
    onUnmatched: () {},
    onSettings: onSettings,
  ),
);

Future<void> _sendMenuItem() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .handlePlatformMessage(
      'anilocal/window',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('settingsRequested'),
      ),
      (_) {},
    );

void main() {
  group('the Settings key', () {
    testWidgets("⌘, fires the top page's own settings action", (tester) async {
      var opened = 0;
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(home: SpecPage(spec: _withSettings(() => opened++))),
      );
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.metaLeft);
      expect(opened, 1);

      // Either modifier, on every platform — nothing else binds Ctrl+, here.
      await _press(tester, LogicalKeyboardKey.controlLeft);
      expect(opened, 2);
    });

    testWidgets('a bare comma is just a comma', (tester) async {
      var opened = 0;
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(home: SpecPage(spec: _withSettings(() => opened++))),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.pump();
      expect(opened, 0);
    });

    testWidgets('a page with no app actions: nothing happens, nothing throws', (
      tester,
    ) async {
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(
          home: const SpecPage(spec: HeaderSpec(title: 'Fix match')),
        ),
      );
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.metaLeft);
      expect(h.controller.openSettings(), isFalse, reason: 'fails ABSENT');
    });

    testWidgets('while a dialog is up, the key is ignored', (tester) async {
      // Settings itself is a dialog: a second window over the first is a
      // trap, and the ⚙ is not reachable then either.
      var opened = 0;
      final h = ShellHarness();
      await tester.pumpWidget(
        h.app(home: SpecPage(spec: _withSettings(() => opened++))),
      );
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: h.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('a dialog')),
        ),
      );
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.metaLeft);
      expect(opened, 0);

      h.pop();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.metaLeft);
      expect(opened, 1, reason: 'the door reopens with the dialog gone');
    });

    testWidgets('the menu bar item lands on the same action', (tester) async {
      var opened = 0;
      final h = ShellHarness();
      WindowChrome.ensureInitialized();
      await tester.pumpWidget(
        h.app(home: SpecPage(spec: _withSettings(() => opened++))),
      );
      await tester.pump();

      await _sendMenuItem();
      await tester.pump();
      expect(opened, 1);
    });
  });
}
