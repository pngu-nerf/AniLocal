import 'package:anilocal/ui/theater/controls/player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the crash fix: the player reads fullscreen state WITHOUT subscribing
/// to the (route-scoped) inherited widget, so it can never become a dependent
/// that outlives the inherited element and trips `_dependents.isEmpty` on
/// back-navigation.
///
/// We can't construct media_kit's real FullscreenInheritedWidget here (it needs
/// a live VideoState), so we exercise the exact mechanism `playerIsFullscreen`
/// delegates to — [hasInheritedAncestorWithoutSubscribing] — against a stand-in
/// inherited widget. A regression (switching back to a subscribing read) makes
/// the non-subscribing reader start rebuilding and fails this test.
class _StandIn extends InheritedWidget {
  const _StandIn({required this.value, required super.child});
  final int value;
  @override
  bool updateShouldNotify(_StandIn oldWidget) => oldWidget.value != value;
}

class _Host extends StatefulWidget {
  const _Host({required this.child});
  final Widget child;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int value = 0;
  void bump() => setState(() => value++);
  @override
  Widget build(BuildContext context) {
    // widget.child is a STABLE instance — it only rebuilds if it has registered
    // an inherited dependency, not because this State rebuilt.
    return _StandIn(value: value, child: widget.child);
  }
}

void main() {
  testWidgets('non-subscribing inherited read registers no dependency', (
    tester,
  ) async {
    var subscribingBuilds = 0;
    var nonSubscribingBuilds = 0;

    final child = Column(
      children: [
        Builder(
          builder: (context) {
            // The subscribing pattern (what we removed): rebuilds on change.
            context.dependOnInheritedWidgetOfExactType<_StandIn>();
            subscribingBuilds++;
            return const SizedBox.shrink();
          },
        ),
        Builder(
          builder: (context) {
            // The fix's mechanism: must NOT rebuild on change.
            hasInheritedAncestorWithoutSubscribing<_StandIn>(context);
            nonSubscribingBuilds++;
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: _Host(child: child)));
    expect(subscribingBuilds, 1);
    expect(nonSubscribingBuilds, 1);

    // Change the inherited widget's value (updateShouldNotify -> true).
    tester.state<_HostState>(find.byType(_Host)).bump();
    await tester.pump();

    expect(
      subscribingBuilds,
      2,
      reason: 'a dependOn... reader rebuilds on the inherited change',
    );
    expect(
      nonSubscribingBuilds,
      1,
      reason:
          'the non-subscribing reader must NOT rebuild — proves it '
          'registered no dependency, so it can never trip _dependents.isEmpty',
    );
  });
}
