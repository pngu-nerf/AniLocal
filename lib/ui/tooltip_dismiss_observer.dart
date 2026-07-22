import 'package:flutter/material.dart';

/// A [NavigatorObserver] that dismisses any showing tooltip on every route
/// transition, installed on the root navigator ([MaterialApp.navigatorObservers]).
///
/// media_kit's fullscreen enter/exit pushes/pops a route on the ROOT navigator
/// AND resizes the window. A tooltip that's mounted across that resize crashes:
/// its deferred `OverlayPortal` child re-lays-out against the now-stale overlay
/// size and asserts (`overlay.dart` `size == theater.size` — the originating
/// error behind the fullscreen-exit red screen). Because every fullscreen entry
/// AND exit — the ⛶ button, the Escape shortcut, and the macOS green
/// traffic-light / native exit (which media_kit drives through this navigator's
/// pop) — is a transition here, dismissing tooltips on transition closes all of
/// them in ONE place, and any future exit path is covered automatically.
///
/// It ONLY calls [Tooltip.dismissAllToolTips]; it touches no route, focus, or
/// fullscreen state, so it can't interfere with the `playerIsFullscreen`
/// non-subscribing guard, the click-to-pause hit-testing, or focus ownership.
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
