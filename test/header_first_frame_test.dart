import 'package:anilocal/domain/models/sync_control.dart';
import 'package:anilocal/ui/shell/header_controller.dart';
import 'package:anilocal/ui/shell/header_scope.dart';
import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// A page that publishes from its very first build — what every real page
/// does — and records whether the controller notified WHILE a build was in
/// progress (the framework forbids marking an ancestor dirty then).
class _PublishingPage extends StatefulWidget {
  const _PublishingPage({required this.onNotify});
  final void Function(bool building) onNotify;
  @override
  State<_PublishingPage> createState() => _PublishingPageState();
}

class _PublishingPageState extends State<_PublishingPage> {
  @override
  Widget build(BuildContext context) {
    final controller = HeaderScope.of(context);
    controller.addListener(_onNotify);
    controller.publish(
      ModalRoute.of(context)!,
      const HeaderSpec(title: 'First'),
    );
    return const SizedBox.shrink();
  }

  void _onNotify() =>
      widget.onNotify(WidgetsBinding.instance.buildOwner!.debugBuilding);
}

/// The header's first frame. `runApp` builds the first tree from a timer
/// callback — scheduler phase IDLE, BuildOwner building — and a notification
/// there used to be thrown away, leaving no title and no actions until a
/// window resize. The contract: the controller never notifies synchronously
/// from inside a build, and the first publish still reaches the shell.
void main() {
  testWidgets('a publish during the first build notifies AFTER it, once', (
    tester,
  ) async {
    final h = ShellHarness();
    final seen = <bool>[];
    await tester.pumpWidget(h.app(home: _PublishingPage(onNotify: seen.add)));
    expect(seen, isNotEmpty, reason: 'the publish was delivered');
    expect(
      seen.every((building) => !building),
      isTrue,
      reason: 'never while the BuildOwner is building',
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is VfdReadout && w.text == 'First'),
      findsOneWidget,
      reason: 'the title is on screen with no nudge',
    );
  });

  test(
    'publish outside a frame notifies asynchronously, never inline',
    () async {
      // `runApp` builds the first tree OUTSIDE any frame (scheduler idle, a
      // timer callback), which the widget-test binding cannot reproduce — it
      // attaches inside a frame. So the contract is pinned directly: a publish
      // in the idle phase must not reach listeners before it returns.
      TestWidgetsFlutterBinding.ensureInitialized();
      final controller = HeaderController(navigatorKey: GlobalKey());
      addTearDown(controller.dispose);
      var notified = 0;
      var returned = false;
      controller.addListener(() {
        expect(returned, isTrue, reason: 'a synchronous notify is the bug');
        notified++;
      });
      final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      controller.onTopChanged(route);
      controller.publish(route, const HeaderSpec(title: 'First'));
      returned = true;
      expect(notified, 0);
      await Future<void>.delayed(Duration.zero);
      expect(notified, 1, reason: 'delivered once, coalesced');
    },
  );

  test('the scan status fits the readout and moves per title', () {
    expect(scanningTitle(null), 'Scanning…');
    expect(
      scanningTitle(
        const SyncProgress(done: 12, total: 340, phase: 'identifying'),
      ),
      'Identifying 12/340',
    );
    expect(
      scanningTitle(const SyncProgress(done: 4, total: 4, phase: 'metadata')),
      'Metadata…',
    );
    expect(
      scanningTitle(const SyncProgress(done: 120, total: 600, phase: 'skips')),
      'Identifying skips 120/600',
    );
    expect(
      scanningTitle(const SyncProgress(done: 0, total: 20, phase: 'airing')),
      'Checking airing…',
      reason: 'the airing pass reports as a whole',
    );
    // Every character of every status paints as a glyph, not a hole.
    for (final s in [
      scanningTitle(null),
      scanningTitle(
        const SyncProgress(done: 12, total: 340, phase: 'identifying'),
      ),
      scanningTitle(const SyncProgress(done: 1, total: 1, phase: 'metadata')),
    ]) {
      expect(vfdHasGlyphs(s), isTrue, reason: s);
    }
  });

  test('the dot-matrix font covers real titles and their punctuation', () {
    for (final title in const [
      "Frieren: Beyond Journey's End",
      'Frieren: Beyond Journey’s End',
      'Re:ZERO -Starting Life in Another World- Season 3',
      'Mob Psycho 100 II',
      'K-On!',
      '86 EIGHTY-SIX (Part 2)',
      'Oshi no Ko — 2nd Season',
      'Library · identifying',
      'Bocchi the Rock! & Friends, Vol. 2 #1 @ 100%',
      'Not in library…',
    ]) {
      expect(vfdHasGlyphs(title), isTrue, reason: title);
    }
    // A blank is what an unknown character paints — and the width still
    // counts it, so the two must agree: the ellipsis is three cells.
    expect(
      VfdReadout.widthFor('a…', dotPitch: 1),
      VfdReadout.widthFor('a...', dotPitch: 1),
    );
  });
}
