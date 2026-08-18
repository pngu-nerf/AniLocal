import 'package:anilocal/ui/theater/controls/player_control_bar.dart';
import 'package:anilocal/ui/theater/controls/player_controls_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Locks in the Slice-2 structural fix: **fullscreen is STATE, not a route.**
///
/// This file replaces `player_fullscreen_no_subscribe_test.dart`, which guarded
/// the old workaround (a non-subscribing read of media_kit's route-scoped
/// `FullscreenInheritedWidget`, to dodge `_dependents.isEmpty` on fullscreen
/// exit). That workaround is gone because its cause is gone. Guarding the
/// removal is now the useful thing: if anyone reintroduces a route-based
/// fullscreen, the crash class comes back, and these tests fail.
///
/// What the crash needed: a second route holding a second `Video` over the same
/// `VideoState`, so a control could subscribe to an inherited widget that
/// outlives it. Kill the route and the precondition cannot be assembled — so
/// the assertions below are about "no route" and "mode comes from state".

const Stream<Never> _empty = Stream<Never>.empty();

class _StubPlayer implements Player {
  int playOrPauseCalls = 0;

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
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #playOrPause) playOrPauseCalls++;
    return Future<void>.value();
  }
}

/// Counts route pushes/pops so a fullscreen toggle can be proven route-free.
class _RouteCounter extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  late ValueNotifier<PlayerControlsState> state;
  late int toggles;
  late _RouteCounter routes;

  Widget app() {
    return MaterialApp(
      navigatorObservers: [routes],
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: PlayerControls(
            player: _StubPlayer(),
            state: state,
            actions: PlayerControlsActions(
              skipIntro: () {},
              skipOutro: () {},
              playNext: () {},
              cancelPreRoll: () {},
              // What the theater does for real: flip state. No Navigator.
              toggleFullscreen: () {
                toggles++;
                state.value = state.value.copyWith(
                  fullscreen: !state.value.fullscreen,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    state = ValueNotifier(const PlayerControlsState());
    toggles = 0;
    routes = _RouteCounter();
  });

  testWidgets('the fullscreen button pushes NO route — it flips state', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    final baseline = routes.pushes;

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pump();

    expect(toggles, 1);
    expect(state.value.fullscreen, isTrue);
    expect(
      routes.pushes,
      baseline,
      reason:
          'a fullscreen ROUTE is the precondition for the '
          '_dependents.isEmpty crash — there must not be one',
    );
    expect(routes.pops, 0);
  });

  testWidgets('the button renders from state, both ways, with no route churn', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    // MaterialApp's own `home` push counts; baseline it out.
    final baseline = routes.pushes + routes.pops;
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);

    // Drive the mode the way the theater does — externally, via the notifier.
    state.value = state.value.copyWith(fullscreen: true);
    await tester.pump();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen), findsNothing);

    state.value = state.value.copyWith(fullscreen: false);
    await tester.pump();
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(routes.pushes + routes.pops, baseline);
  });

  testWidgets('the player no longer handles Escape itself — exiting is the '
      "app-wide backstop's job, in ONE place", (tester) async {
    // Escape used to be handled here too. It isn't any more: `AppShell`
    // registers a HardwareKeyboard handler that exits fullscreen before focus
    // dispatch even reaches this overlay, so a copy here would be dead code
    // that looks load-bearing. What this pins is that the player doesn't
    // quietly re-acquire it — and, importantly, that Escape is not swallowed
    // here when windowed.
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(toggles, 0);

    state.value = state.value.copyWith(fullscreen: true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      toggles,
      0,
      reason: 'the player must not duplicate the global Escape rule',
    );
    expect(routes.pops, 0, reason: 'and Escape never pops a route');
  });

  testWidgets('a fullscreen change RECLAIMS keyboard focus, so the next '
      'Escape lands on the first press', (tester) async {
    // The bug this guards: the macOS fullscreen transition moves the window to
    // another Space, the NSWindow resigns/regains key, and Flutter drops the
    // overlay's primary focus. Every other reclaim path is a pointer or mount
    // event, so a user who toggled fullscreen and then hit Escape got nothing —
    // the first press was swallowed and a second was needed. The reclaim now
    // rides the fullscreen signal itself.
    await tester.pumpWidget(app());
    await tester.pump(); // autofocus settles

    FocusNode? ownedNode() => tester
        .widgetList<Focus>(find.byType(Focus))
        .firstWhere((w) => w.focusNode?.debugLabel == 'AniLocal player')
        .focusNode;

    expect(ownedNode()?.hasPrimaryFocus, isTrue);

    // Simulate the transition stealing focus (what the Space switch does).
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    expect(ownedNode()?.hasPrimaryFocus, isFalse);

    // The window reports it is now fullscreen -> the flag reaches the overlay.
    state.value = state.value.copyWith(fullscreen: true);
    await tester.pump();
    expect(
      ownedNode()?.hasPrimaryFocus,
      isTrue,
      reason: 'the fullscreen change must reclaim focus',
    );

    // …and the behavioural consequence: a shortcut lands on the FIRST press.
    // (Space rather than Escape — Escape is the app-wide backstop's now, but
    // the focus-reclaim this guards is what makes every player shortcut work.)
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      (tester.widget<PlayerControls>(find.byType(PlayerControls)).player
              as _StubPlayer)
          .playOrPauseCalls,
      1,
      reason: 'a single keypress must reach the player after a mode change',
    );
  });
}
