import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/ui/theater/controls/player_controls.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/widgets/show_cover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'support/recording_player.dart';

/// The per-frame and per-event costs the audit measured, pinned as
/// contracts: covers decode at display size, the time readout redraws per
/// second not per position event, the header marquee rests after its passes,
/// and every dot-matrix readout paints in its own layer.
void main() {
  group('ShowCover', () {
    testWidgets('decodes at the laid-out width × device pixel ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      // Any path: the provider is built before anything is decoded, and a
      // missing file only ever reaches the placeholder.
      const path = '/nowhere/c.jpg';
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 150,
              height: 210,
              child: ShowCover(
                imagePath: path,
                pictureMode: PictureMode.normal,
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image;
      expect(provider, isA<ResizeImage>(), reason: 'cacheWidth is set');
      expect((provider as ResizeImage).width, 300, reason: '150 px × 2.0');
    });
  });

  group('TimeLabel', () {
    testWidgets('redraws when the SECOND changes, not per position event', (
      tester,
    ) async {
      final player = RecordingPlayer(
        state: const PlayerState(duration: Duration(minutes: 24)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: XpTheme.data(),
          home: Scaffold(
            body: Center(child: TimeLabel(player: player)),
          ),
        ),
      );
      String readout() =>
          tester.widget<VfdReadout>(find.byType(VfdReadout)).text;
      expect(readout(), startsWith('0:00'));
      var paints = 0;
      // Count readout rebuilds through its element: a new VfdReadout instance
      // per StreamBuilder rebuild.
      final before = tester.widget<VfdReadout>(find.byType(VfdReadout));
      player.emitPosition(const Duration(milliseconds: 1200));
      await tester.pump();
      player.emitPosition(const Duration(milliseconds: 1400));
      await tester.pump();
      player.emitPosition(const Duration(milliseconds: 1900));
      await tester.pump();
      final after = tester.widget<VfdReadout>(find.byType(VfdReadout));
      expect(readout(), startsWith('0:01'));
      paints += identical(before, after) ? 0 : 1;
      // Three events inside one second: exactly one rebuild (the 0:00 → 0:01
      // change), not three.
      expect(paints, 1);
      final atOne = after;
      player.emitPosition(const Duration(milliseconds: 1950));
      await tester.pump();
      expect(
        identical(atOne, tester.widget<VfdReadout>(find.byType(VfdReadout))),
        isTrue,
        reason: 'same second, no rebuild',
      );
      player.emitPosition(const Duration(seconds: 2));
      await tester.pump();
      expect(readout(), startsWith('0:02'));
    });
  });

  group('VfdReadout', () {
    testWidgets('paints in its own layer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: VfdReadout('EP 1'))),
      );
      expect(
        find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });

  group('the header marquee', () {
    testWidgets('scrolls its passes, then rests at the start', (tester) async {
      // A title far wider than the readout, in a narrow screen.
      const title = 'An Extremely Long Show Title That Cannot Possibly Fit';
      await tester.pumpWidget(
        MaterialApp(
          theme: XpTheme.data(),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 160, child: HeaderReadout(title: title)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue, reason: 'first pass');
      // Each pass ends on a frame at or past its duration, then the next one
      // starts — so pump a frame at a time, generously past three passes of a
      // long title at 32 px/s.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 15));
      }
      await tester.pump();
      expect(
        tester.hasRunningAnimations,
        isFalse,
        reason:
            'rests after its passes instead of ~800 blurred dots a frame '
            'forever',
      );
      // Hovering wakes it for another set.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HeaderReadout)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue, reason: 'woken by hover');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 15));
      }
    });
  });
}
