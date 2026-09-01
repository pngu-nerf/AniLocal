import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/ui/theater/controls/control_bar_config.dart';
import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:anilocal/ui/theater/controls/seek_bar.dart';
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

/// Native-free stand-in so the controls can build in the harness.
class _StubPlayer implements Player {
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

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
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
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      height: 300,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PlayerControlBar(
          player: _StubPlayer(),
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
