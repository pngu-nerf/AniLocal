import 'package:anilocal/ui/shell/app_shell.dart';
import 'package:anilocal/ui/shell/header_controller.dart';
import 'package:anilocal/ui/shell/header_scope.dart';
import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:flutter/material.dart';

/// Mirrors `AniLocalApp`'s shell wiring for tests: one hoisted header above a
/// Navigator, fed by pages that publish a [HeaderSpec].
///
/// Kept in one place so header tests exercise the REAL shell (`AppShell`,
/// `HeaderController`, `HeaderRouteObserver`) rather than a lookalike — a
/// harness that re-implemented the wiring could pass while production broke.
class ShellHarness {
  ShellHarness() {
    controller = HeaderController(navigatorKey: navigatorKey);
    observer = HeaderRouteObserver(controller);
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final HeaderController controller;
  late final HeaderRouteObserver observer;

  Widget app({required Widget home}) => MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    builder: (context, child) => HeaderScope(
      controller: controller,
      child: AppShell(child: child!),
    ),
    home: home,
  );

  /// Push another page onto the shell's navigator.
  ///
  /// Returns VOID on purpose: `Navigator.push` hands back a future that
  /// completes when the route is POPPED, so awaiting it in a test hangs
  /// forever. Making that un-awaitable removes the trap.
  void push(Widget page) {
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => page));
  }

  /// Push a page that opts OUT of the shell chrome (what the theater does).
  void pushChromeless(Widget page) {
    navigatorKey.currentState!.push(ChromelessPageRoute(builder: (_) => page));
  }

  void pop() => navigatorKey.currentState!.pop();
}

/// A page that publishes a fixed spec — the common case in tests.
class SpecPage extends StatefulWidget {
  const SpecPage({super.key, required this.spec, this.body});

  final HeaderSpec spec;
  final Widget? body;

  @override
  State<SpecPage> createState() => SpecPageState();
}

class SpecPageState extends State<SpecPage> with HeaderPublisher {
  /// Lets a test mutate live state (e.g. flip `scanning`) the way a real page
  /// does — via setState, which fires neither initState nor didUpdateWidget.
  HeaderSpec? _override;

  void update(HeaderSpec spec) => setState(() => _override = spec);

  @override
  HeaderSpec buildHeaderSpec() => _override ?? widget.spec;

  @override
  Widget build(BuildContext context) {
    publishHeader();
    return widget.body ?? const SizedBox.shrink();
  }
}

/// A page that publishes NOTHING — the degradation case.
class SilentPage extends StatelessWidget {
  const SilentPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
