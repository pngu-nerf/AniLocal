import 'package:anilocal/ui/shell/app_shell.dart';
import 'package:anilocal/ui/shell/header_controller.dart';
import 'package:anilocal/ui/shell/header_scope.dart';
import 'package:anilocal/ui/shell/header_spec.dart';
import 'package:anilocal/ui/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // The controller outlives the widget tree (it's app-lifetime in production),
    // so a test must dispose it or its grace timer is left pending at teardown.
    addTearDown(controller.dispose);
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final HeaderController controller;
  late final HeaderRouteObserver observer;

  /// Mirrors AniLocalApp: the controller is handed to the shell directly (the
  /// shell subscribes to it), while HeaderScope exists so PAGES can publish.
  /// The no-transition theme is part of the wiring too, so tests see the same
  /// instant navigation the app does.
  Widget app({required Widget home}) => MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    theme: ThemeData(
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values) p: const _NoPageTransition(),
        },
      ),
    ),
    builder: (context, child) => HeaderScope(
      controller: controller,
      child: AppShell(controller: controller, child: child!),
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

  /// Push a page the shell renders WITHOUT its frame (what the player does).
  /// It still shares the one hoisted header.
  void pushFrameless(Widget page) {
    navigatorKey.currentState!.push(FramelessPageRoute(builder: (_) => page));
  }

  /// Drive the REAL fullscreen signal the way the runner does — a
  /// `fullscreenChanged` call on the window channel — rather than poking a
  /// private field, so tests exercise the same path production uses.
  Future<void> setFullscreen(bool value) async {
    WindowChrome.ensureInitialized();
    addTearDown(() => _sendFullscreen(false));
    await _sendFullscreen(value);
  }

  Future<void> _sendFullscreen(bool value) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .handlePlatformMessage(
        'anilocal/window',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('fullscreenChanged', value),
        ),
        (_) {},
      );

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

class _NoPageTransition extends PageTransitionsBuilder {
  const _NoPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
