import 'dart:io';

import 'package:anilocal/domain/models/picture_mode.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/theme/xp_widgets.dart';
import 'package:anilocal/ui/widgets/show_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../support/recording_player.dart';

/// Golden images of the hand-built visual identity — the VFD chrome, the
/// dot-matrix readout, the segmented timeline, the cover tiles. A
/// pixel change here is either intended (regenerate with
/// `flutter test --update-goldens test/goldens`) or a regression in a look
/// that no assertion on widget structure can see.
///
/// Rendered with the BUNDLED Archivo and the SDK's Material icon font, loaded
/// for this file only, so a golden shows the app's real type and glyphs and
/// not the test framework's Ahem boxes. Every other test keeps Ahem: loading
/// a font suite-wide would change the layout widths those tests measure.
///
/// Goldens are rasterised by the Flutter engine, so they are tied to the SDK
/// version: CI pins the same `flutter-version` the images were generated with,
/// and an SDK bump regenerates them in the same commit. Across CPU
/// architectures the engine antialiases a handful of pixels differently, so
/// `flutter_test_config.dart` beside this file compares with a 0.1% tolerance.
void main() {
  setUpAll(() async {
    await (FontLoader(
      'Archivo',
    )..addFont(rootBundle.load('fonts/Archivo-Variable.ttf'))).load();
    // The icon font ships with the SDK, not the app: <sdk>/bin/cache/
    // artifacts/material_fonts. `flutter test` exports FLUTTER_ROOT; failing
    // that, the VM running this test is <sdk>/bin/cache/artifacts/engine/
    // <platform>/flutter_tester.
    final root =
        Platform.environment['FLUTTER_ROOT'] ??
        File(
          Platform.resolvedExecutable,
        ).parent.parent.parent.parent.parent.path;
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    expect(icons.existsSync(), isTrue, reason: 'icon font at ${icons.path}');
    final bytes = await icons.readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  Widget stage(Widget child, {double width = 420, double height = 120}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: XpTheme.data(),
        home: Center(
          child: RepaintBoundary(
            key: const ValueKey('stage'),
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );

  Future<void> golden(WidgetTester tester, Widget w, String name) async {
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('stage')),
      matchesGoldenFile('images/$name.png'),
    );
  }

  group('visual identity goldens', () {
    testWidgets('XpButton — plain, selected, lit, dense', (tester) async {
      await golden(
        tester,
        stage(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              XpButton(label: 'Scan', icon: Icons.refresh, onPressed: () {}),
              XpButton(label: 'Folders', selected: true, onPressed: () {}),
              XpButton(label: 'Play', lit: true, onPressed: () {}),
              XpButton(label: 'Done', dense: true, onPressed: () {}),
            ],
          ),
          width: 520,
          height: 72,
        ),
        'xp_button',
      );
    });

    testWidgets('XpTitleBar', (tester) async {
      await golden(
        tester,
        stage(
          XpTitleBar(
            caption: 'Cowboy Bebop',
            trailing: XpButton(icon: Icons.settings, onPressed: () {}),
          ),
          width: 520,
          height: 56,
        ),
        'xp_title_bar',
      );
    });

    testWidgets('VfdReadout', (tester) async {
      await golden(
        tester,
        stage(
          const ColoredBox(
            color: Colors.black,
            child: Center(child: VfdReadout('EP 12  23:41 / 24:00')),
          ),
          width: 420,
          height: 64,
        ),
        'vfd_readout',
      );
    });

    testWidgets('seek bar with intro and outro markers', (tester) async {
      final player = RecordingPlayer(
        state: const PlayerState(
          duration: Duration(minutes: 24),
          position: Duration(minutes: 8),
        ),
      );
      await golden(
        tester,
        stage(
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: SeekBar(
                player: player,
                introSkip: SkipRange(
                  start: const Duration(seconds: 90),
                  end: const Duration(seconds: 180),
                ),
                outroSkip: SkipRange(
                  start: const Duration(minutes: 22),
                  end: const Duration(minutes: 23, seconds: 30),
                ),
              ),
            ),
          ),
          width: 520,
          height: 40,
        ),
        'seek_bar_markers',
      );
    });

    testWidgets('the VFD control bar, windowed, with a skip button live', (
      tester,
    ) async {
      final player = RecordingPlayer(
        state: const PlayerState(
          duration: Duration(minutes: 24),
          position: Duration(minutes: 1, seconds: 40),
          playing: true,
        ),
      );
      await golden(
        tester,
        stage(
          ColoredBox(
            color: Colors.black,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerControlBar(
                player: player,
                state: ValueNotifier(
                  PlayerControlsState(episode: null, showSkipIntro: true),
                ),
                actions: PlayerControlsActions(
                  skipIntro: () {},
                  skipOutro: () {},
                  playNext: () {},
                  cancelPreRoll: () {},
                  toggleFullscreen: () {},
                ),
              ),
            ),
          ),
          width: 720,
          height: 120,
        ),
        'vfd_control_bar',
      );
    });

    testWidgets('cover placeholder, and the removed tile', (tester) async {
      // Without a cover file `normal` and `blur` both fall to the placeholder
      // and `removed` is the black "?" tile — the two tiles a library shows
      // before art arrives, or after the viewer hides it. (A real decoded
      // image is out of reach here: flutter_tester's image decode does not
      // complete under the test binding's async zone.)
      await golden(
        tester,
        stage(
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 90,
                height: 128,
                child: ShowCover(
                  imagePath: null,
                  pictureMode: PictureMode.normal,
                ),
              ),
              SizedBox(
                width: 90,
                height: 128,
                child: ShowCover(
                  imagePath: null,
                  pictureMode: PictureMode.removed,
                ),
              ),
            ],
          ),
          width: 240,
          height: 140,
        ),
        'show_cover_modes',
      );
    });
  });
}
