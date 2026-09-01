import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/ui/theater/controls/control_bar_config.dart';
import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
import 'package:anilocal/ui/theater/controls/segmented_meter.dart';
import 'package:anilocal/ui/theater/controls/vfd_control.dart';
import 'package:anilocal/ui/theme/xp_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

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

const Stream<Never> _empty = Stream<Never>.empty();

/// Native-free stand-in so the controls can build in the harness. Records the
/// calls the controls make, so a restyled control can be shown to still drive
/// the same player path.
class _StubPlayer implements Player {
  final List<Invocation> calls = [];

  @override
  final PlayerState state = const PlayerState();

  @override
  final PlayerStream stream = const PlayerStream(
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
    _empty,
  );

  double? get volumeSet => calls.isEmpty
      ? null
      : calls
                .lastWhere((c) => c.memberName == #setVolume)
                .positionalArguments
                .first
            as double;

  bool get setVolumeCalled => calls.any((c) => c.memberName == #setVolume);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) calls.add(invocation);
    return Future<void>.value();
  }
}

Episode _ep(int n) => Episode(
  number: n,
  fileRef: '/lib/ep$n.mkv',
  seriesAnilistId: 1,
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
          player: player ?? _StubPlayer(),
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
                player: _StubPlayer(),
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
      final player = _StubPlayer();
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
      expect(player.setVolumeCalled, isTrue, reason: 'tap sets volume');
      expect(player.volumeSet, closeTo(25, 2));

      // Drag reports LIVE, like the slider's onChanged did — not only on
      // release, which is the seek bar's contract and would feel wrong here.
      await tester.drag(meter, const Offset(30, 0));
      await tester.pump();
      expect(player.volumeSet, greaterThan(25));
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
