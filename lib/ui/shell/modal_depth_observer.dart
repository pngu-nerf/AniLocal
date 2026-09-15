import 'package:flutter/widgets.dart';

/// How many NON-page routes (dialogs, menus, popups) sit on the navigator.
///
/// The shell's fullscreen Escape backstop must yield while a dialog is up:
/// it runs before focus dispatch, so with Settings open over a fullscreen
/// player the first Escape left fullscreen instead of closing the window.
/// A depth count is the one signal both sides agree on — pages are what
/// `HeaderRouteObserver` tracks, and everything else is a modal.
class ModalDepthObserver extends NavigatorObserver {
  final ValueNotifier<int> depth = ValueNotifier<int>(0);

  bool _isModal(Route<dynamic> route) => route is! PageRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) depth.value += 1;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route) && depth.value > 0) depth.value -= 1;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route) && depth.value > 0) depth.value -= 1;
  }

  void dispose() => depth.dispose();
}
