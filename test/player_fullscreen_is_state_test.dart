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

  testWidgets('Escape exits fullscreen through the SAME action, and is a '
      'no-op when windowed', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(); // let the overlay's owned focus settle

    // Windowed: Escape must not toggle (and must not swallow the key).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(toggles, 0, reason: 'Escape only EXITS fullscreen');

    state.value = state.value.copyWith(fullscreen: true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(toggles, 1, reason: 'Escape routes through the one toggle action');
    expect(state.value.fullscreen, isFalse);
    expect(routes.pops, 0, reason: 'exiting fullscreen pops nothing');
  });
}
