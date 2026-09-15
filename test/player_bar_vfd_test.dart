import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/episode_source.dart';
import 'package:anilocal/ui/theater/controls/control_bar_config.dart';
import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
import 'package:anilocal/ui/theater/controls/segmented_meter.dart';
import 'package:anilocal/ui/theater/controls/vfd_control.dart';
import 'package:anilocal/ui/theme/header_readout.dart';
import 'package:anilocal/ui/theme/vfd_readout.dart' show VfdReadout;
import 'package:anilocal/ui/theme/xp_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'support/finders.dart';
import 'support/recording_player.dart';

/// The player bar's VFD restyle. What's pinned here is what a later "tidy-up"
/// would silently undo:
///  - the EP readout lives in the SHARED config, so it can't quietly become
///    windowed-only (the historical skip-button-missing-in-fullscreen shape);
///  - the bar's surface is a SOLID panel that still fades with the controls —
///    a permanent strip would sit over the picture forever, which the "picture
///    quality is sacred" rule forbids;
///  - the seek bar is untouched by the restyle;
///  - the readout degrades rather than breaking on a special.
///
/// Look itself (phosphor colours, glow) is deliberately NOT asserted — that is
/// what device verification is for; these are the structural claims.

/// The last volume the controls asked the player for, or null if none.
double? _volumeSet(RecordingPlayer player) => player.called(#setVolume)
    ? player.lastCall(#setVolume).positionalArguments.first as double
    : null;

Episode _ep(int n) => Episode(
  number: n,
  fileRef: '/lib/ep$n.mkv',
  seriesId: 1,
  anchoredNumber: n,
  title: 'Episode $n',
);

final _actions = PlayerControlsActions(
  skipIntro: () {},
  skipOutro: () {},
  playNext: () {},
  cancelPreRoll: () {},
  toggleFullscreen: () {},
);

Widget _bar({
  required PlayerControlsState state,
  double width = 900,
  bool fullscreen = false,
  Player? player,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      height: 300,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PlayerControlBar(
          player: player ?? RecordingPlayer(),
          state: ValueNotifier(
            fullscreen ? state.copyWith(fullscreen: true) : state,
          ),
          actions: _actions,
        ),
      ),
    ),
  ),
);

/// The readout paints dots, not text, so it is found by the Semantics label
/// [VfdReadout] carries for exactly this (and for screen readers).
Finder _readout(String label) => find.bySemanticsLabel(label);

void main() {
  group('the Copy section of the settings menu', () {
    const a = EpisodeSource(
      fileRef: '/usb/ep1.mkv',
      folderPath: '/usb',
      folderSortOrder: 0,
    );
    const b = EpisodeSource(
      fileRef: '/nas/ep1.mkv',
      folderPath: '/nas',
      folderSortOrder: 1,
    );
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('appears for a multi-copy episode when the host can pin', (
      tester,
    ) async {
      EpisodeSource? chosen;
      var cleared = 0;
      final actions = PlayerControlsActions(
        skipIntro: () {},
        skipOutro: () {},
        playNext: () {},
        cancelPreRoll: () {},
        toggleFullscreen: () {},
        selectSource: (s) => s == null ? cleared++ : chosen = s,
      );
      final episode = Episode(
        number: 1,
        anchoredNumber: 1,
        seriesId: 7,
        fileRef: a.fileRef,
        sources: const [a, b],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 300,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: PlayerControlBar(
                  player: RecordingPlayer(),
                  state: ValueNotifier(PlayerControlsState(episode: episode)),
                  actions: actions,
                ),
              ),
            ),
          ),
        ),
      );
      await openSettings(tester);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(find.text('usb › ep1.mkv'), findsOneWidget);
      await tester.tap(find.text('nas › ep1.mkv'));
      await tester.pumpAndSettle();
      expect(chosen, b);
      expect(cleared, 0);
    });

    testWidgets('is absent for a single-copy episode', (tester) async {
      final episode = Episode(
        number: 1,
        anchoredNumber: 1,
        seriesId: 7,
        fileRef: a.fileRef,
        sources: const [a],
      );
      // The host CAN pin — the section is absent because there is only one
      // copy, not because the action is missing.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 300,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: PlayerControlBar(
                  player: RecordingPlayer(),
                  state: ValueNotifier(PlayerControlsState(episode: episode)),
                  actions: PlayerControlsActions(
                    skipIntro: () {},
                    skipOutro: () {},
                    playNext: () {},
                    cancelPreRoll: () {},
                    toggleFullscreen: () {},
                    selectSource: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await openSettings(tester);
      expect(find.text('Playback speed'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('the error notice', () {
    testWidgets('carries Retry, and the copy notice is a plain line', (
      tester,
    ) async {
      var retries = 0;
      final state = ValueNotifier(
        PlayerControlsState(
          episode: _ep(1),
          errorMessage: 'Cannot open /usb/ep1.mkv',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 300,
              // The notice lives in the OVERLAY (PlayerControls), over the
              // frame, not in the bar.
              child: PlayerControls(
                player: RecordingPlayer(),
                state: state,
                actions: PlayerControlsActions(
                  skipIntro: () {},
                  skipOutro: () {},
                  playNext: () {},
                  cancelPreRoll: () {},
                  toggleFullscreen: () {},
                  retry: () => retries++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Couldn’t play this episode'), findsOneWidget);
      await tester.tap(findXpLabel('Retry'));
      await tester.pump();
      expect(retries, 1);

      state.value = PlayerControlsState(
        episode: _ep(1),
        notice: 'Playing the copy in nas instead',
      );
      await tester.pump();
      expect(find.text('Playing the copy in nas instead'), findsOneWidget);
      expect(find.text('Couldn’t play this episode'), findsNothing);
      expect(findXpLabel('Retry'), findsNothing);
    });
  });

  group('the EP readout is one control in the shared config', () {
    test('it sits in the centre slot, and both modes get the SAME set', () {
      expect(ControlBarConfig.windowedDefault.controlsIn(ControlSlot.center), [
        PlayerControl.episode,
      ]);
      expect(
        ControlBarConfig.fullscreenDefault,
        same(ControlBarConfig.windowedDefault),
        reason:
            'fullscreen must stay a config OF the windowed set, not a fork — '
            'that is what stops a control being silently dropped in one mode',
      );
    });

    test('the legend degrades instead of breaking', () {
      expect(EpisodeReadout.labelFor(_ep(12)), 'EP 12');
      expect(EpisodeReadout.labelFor(_ep(1)), 'EP 1');
      // Specials/extras are modelled as position <= 0 — there is no sensible
      // number to print, so the readout names the kind instead of "EP 0".
      expect(EpisodeReadout.labelFor(_ep(0)), 'SPECIAL');
      expect(EpisodeReadout.labelFor(_ep(-1)), 'SPECIAL');
      expect(EpisodeReadout.labelFor(null), isNull);
    });

    testWidgets('it renders in BOTH modes, and yields the room when narrow', (
      tester,
    ) async {
      final state = PlayerControlsState(episode: _ep(12));

      await tester.pumpWidget(_bar(state: state));
      expect(_readout('EP 12'), findsOneWidget);

      await tester.pumpWidget(_bar(state: state, fullscreen: true));
      expect(
        _readout('EP 12'),
        findsOneWidget,
        reason: 'same bar, same config',
      );

      // Below the bar's compact breakpoint a dot-matrix readout cannot
      // ellipsize, so it drops out rather than squeezing the transport.
      await tester.pumpWidget(_bar(state: state, width: 400));
      expect(_readout('EP 12'), findsNothing);
    });
  });

  testWidgets(
    'the surface is a solid panel that still FADES with the controls',
    (tester) async {
      // The panel lives in the overlay (PlayerControls), not the bar, so this
      // pumps the overlay — the same widget media_kit renders over the texture.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: PlayerControls(
                player: RecordingPlayer(),
                state: ValueNotifier(PlayerControlsState(episode: _ep(3))),
                actions: _actions,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final decorated = find.byWidgetPredicate((w) {
        final d = w is DecoratedBox ? w.decoration : null;
        return d is BoxDecoration && d.color == Xp.well;
      });
      expect(
        decorated,
        findsWidgets,
        reason: 'the bar sits on a true-black display panel',
      );
      expect(
        find.byWidgetPredicate((w) {
          final d = w is DecoratedBox ? w.decoration : null;
          return d is BoxDecoration && d.gradient != null;
        }),
        findsNothing,
        reason: 'the transparent→black scrim ramp is gone',
      );
      expect(
        find.ancestor(of: decorated, matching: find.byType(AnimatedOpacity)),
        findsWidgets,
        reason:
            'the panel must fade WITH the controls — a permanent strip would '
            'cover the bottom of the picture forever',
      );
    },
  );

  volumeGroup();

  testWidgets('the seek bar is left exactly as it was', (tester) async {
    await tester.pumpWidget(_bar(state: PlayerControlsState(episode: _ep(3))));
    expect(find.byType(SeekBar), findsOneWidget);
    expect(
      ControlBarConfig.windowedDefault.controlsIn(ControlSlot.scrubber),
      [PlayerControl.seekBar],
      reason: 'the scrubber slot is the seek bar and nothing else',
    );
  });
}

/// The volume control was the last stock Material widget on the panel: a solid
/// continuous slider among quantized lit cells. These pin that it is now the
/// seek bar's meter — the same cells, one definition — and that it is still a
/// CONTROL, not a picture of one.
void volumeGroup() {
  group('the volume level is the seek bar\'s meter, driven as a control', () {
    testWidgets('the Material slider is gone, replaced by the shared meter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bar(state: PlayerControlsState(episode: _ep(3))),
      );
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(VfdLevelMeter), findsOneWidget);
    });

    testWidgets('it still sets the volume — tap and drag, live', (
      tester,
    ) async {
      final player = RecordingPlayer();
      await tester.pumpWidget(
        _bar(
          state: PlayerControlsState(episode: _ep(3)),
          player: player,
        ),
      );
      final meter = find.byType(VfdLevelMeter);

      // Tap a quarter of the way along → a quarter volume. The mapping is the
      // pointer position, exactly as the slider's was.
      final rect = tester.getRect(meter);
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await tester.pump();
      expect(player.called(#setVolume), isTrue, reason: 'tap sets volume');
      expect(_volumeSet(player), closeTo(25, 2));

      // Drag reports LIVE, like the slider's onChanged did — not only on
      // release, which is the seek bar's contract and would feel wrong here.
      await tester.drag(meter, const Offset(30, 0));
      await tester.pump();
      expect(_volumeSet(player), greaterThan(25));
    });

    testWidgets('it is spoken, though it is only painted', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _bar(state: PlayerControlsState(episode: _ep(3))),
      );
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'it folds away with the rest of the volume control when narrow',
      (tester) async {
        await tester.pumpWidget(
          _bar(state: PlayerControlsState(episode: _ep(3)), width: 400),
        );
        expect(
          find.byType(VfdLevelMeter),
          findsNothing,
          reason: 'compact keeps the mute glyph and drops the level, as before',
        );
      },
    );

    test('one readout size, sitting level with the glyphs beside it', () {
      // 7 dots tall, so the pitch IS the type size. It has to stay in the band
      // the Material glyphs actually draw inside their 20pt boxes (~12-15pt) —
      // at pitch 3 the text stood 21pt and towered over the icon row.
      expect(kVfdBarPitch * 7, inInclusiveRange(12, 16));
      expect(
        kVfdBarPitch,
        HeaderReadout.pitch,
        reason: 'a line of text on a screen is one size app-wide',
      );
    });

    test('one cell geometry, shared by both meters', () {
      // The numbers ARE the look; a second copy is how two meters drift apart.
      expect(VfdMeter.pitch, VfdMeter.cellWidth + VfdMeter.cellGap);
      expect(VfdMeter.cellsAcross(VfdMeter.pitch * 10), 10);
      expect(VfdMeter.cellsAcross(0), 1, reason: 'never divides to nothing');
    });
  });

  group('the icon controls carry a lit/unlit state', () {
    testWidgets('the transport etches BOTH legends and lights the true one', (
      tester,
    ) async {
      // The stub player reports playing:false, so PAUSE is the current state.
      await tester.pumpWidget(
        _bar(state: PlayerControlsState(episode: _ep(3))),
      );

      final litGlyph = tester.widget<Icon>(find.byIcon(Icons.pause));
      final ghostGlyph = tester.widget<Icon>(find.byIcon(Icons.play_arrow));
      expect(
        litGlyph.color!.a,
        1.0,
        reason: 'the state the player is in is fully lit',
      );
      expect(
        ghostGlyph.color!.a,
        closeTo(VfdMeter.unlitAlpha, 0.001),
        reason:
            'the other legend is etched but dark — and at the SAME level an '
            'unlit meter cell uses, so both read as one display',
      );
    });

    testWidgets('no Material ink washes over the phosphor', (tester) async {
      await tester.pumpWidget(
        _bar(state: PlayerControlsState(episode: _ep(3))),
      );
      final buttons = tester
          .widgetList<IconButton>(
            find.descendant(
              of: find.byType(VfdIconButton),
              matching: find.byType(IconButton),
            ),
          )
          .toList();
      expect(buttons, isNotEmpty);
      for (final b in buttons) {
        expect(
          b.style?.splashFactory,
          NoSplash.splashFactory,
          reason: 'a lit element brightens; it does not ripple grey',
        );
      }
    });
  });
}
