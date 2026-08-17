import 'package:flutter/material.dart';

/// # The tooltip-crash guard, in two halves
///
/// **The crash:** a tooltip mounted across a change in the overlay's size
/// crashes — its deferred `OverlayPortal` child re-lays-out against the stale
/// size and asserts (`overlay.dart` `size == theater.size`, the originating
/// error behind the fullscreen-exit red screen). So a showing tooltip must be
/// dismissed *before* anything resizes the overlay.
///
/// It used to be enough to watch ROUTE transitions, because fullscreen was a
/// route: media_kit pushed/popped on the root navigator AND resized the window,
/// so the pop was a reliable proxy for the resize.
///
/// **Fullscreen is now state, not a route — so the route hook alone is no longer
/// sufficient.** Entering/exiting fullscreen resizes the window with no push or
/// pop to observe. The resize half of the trigger did NOT go away with the
/// route, so the guard is now two complementary hooks, and BOTH must stay:
///
/// 1. [TooltipDismissingRouteObserver] — still installed on the root navigator.
///    Fullscreen no longer goes through it, but every other transition does
///    (theater push/pop, settings, dialogs), and those resize the overlay too.
/// 2. [TooltipDismissOnResize] — mounted once above the app. Fires on any
///    window-metrics change, which is what fullscreen now produces. This is the
///    hook that replaces the route observer *for fullscreen specifically*.
///
/// Plus a third, belt-and-braces: the fullscreen toggle itself dismisses
/// tooltips synchronously *before* asking the OS to resize (see
/// `TheaterScreen._toggleFullscreen`), so the common path never even races the
/// metrics callback.
///
/// Both hooks ONLY call [Tooltip.dismissAllToolTips]; they touch no route,
/// focus, or fullscreen state, so neither can interfere with click-to-pause
/// hit-testing or focus ownership.
///
/// A [NavigatorObserver] that dismisses any showing tooltip on every route
/// transition, installed on the root navigator ([MaterialApp.navigatorObservers]).
class TooltipDismissingRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Tooltip.dismissAllToolTips();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Tooltip.dismissAllToolTips();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      Tooltip.dismissAllToolTips();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      Tooltip.dismissAllToolTips();
}

/// Dismisses any showing tooltip whenever the window's metrics change — the
/// half of the tooltip guard that survives fullscreen becoming state.
///
/// Mount ONCE, above the app (see `AniLocalApp`). [didChangeMetrics] fires on
/// every window resize, which now includes fullscreen enter/exit (the OS window
/// toggles with no route push to observe), plus ordinary user resizes and
/// display changes — all of which move the overlay and can strand a mounted
/// tooltip.
///
/// **Do not delete this thinking the route observer covers it.** It does not:
/// with fullscreen off the navigator, there is no push/pop on that transition
/// at all. Removing this brings back the `size == theater.size` crash on
/// fullscreen exit — see `docs/player-crash-repro.md`.
class TooltipDismissOnResize extends StatefulWidget {
  const TooltipDismissOnResize({super.key, required this.child});

  final Widget child;

  @override
  State<TooltipDismissOnResize> createState() => _TooltipDismissOnResizeState();
}

class _TooltipDismissOnResizeState extends State<TooltipDismissOnResize>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Runs before the frame that would re-lay-out the stranded tooltip against
    // the new overlay size, which is the layout that asserts.
    Tooltip.dismissAllToolTips();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
