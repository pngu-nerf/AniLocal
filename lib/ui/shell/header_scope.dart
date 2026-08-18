import 'package:flutter/widgets.dart';

import 'header_controller.dart';
import 'header_spec.dart';

/// Makes the hoisted header's [HeaderController] reachable from any page.
class HeaderScope extends InheritedNotifier<HeaderController> {
  const HeaderScope({
    super.key,
    required HeaderController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Subscribing read — for the shell, which must rebuild when the header
  /// changes.
  static HeaderController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HeaderScope>();
    assert(scope != null, 'No HeaderScope above this context');
    return scope!.notifier!;
  }

  /// NON-subscribing read — for pages, which PUBLISH to the header and must not
  /// rebuild when it changes. A page that depended on this would rebuild every
  /// time it published, which republishes, which rebuilds…
  static HeaderController? maybeReadOf(BuildContext context) => context
      .getElementForInheritedWidgetOfExactType<HeaderScope>()
      ?.widget
      .let((w) => (w as HeaderScope).notifier);
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Mixin for the five shell pages: describe your header, and this keeps the one
/// hoisted header in sync with it.
///
/// **Called FROM `build`, so live state is always current** — the scan spinner
/// and the unmatched count change via `setState`, which fires neither
/// `initState` nor `didUpdateWidget`, so a lifecycle-only publish would freeze
/// them. Equal specs are dropped by the controller, so a rebuild that didn't
/// change the header costs nothing, and the controller defers its notification
/// out of the build phase.
///
/// Why not publish only in `initState`/`didUpdateWidget`: `setState` fires
/// neither. The library's scan spinner changes that way, so a lifecycle-only
/// publish would leave the header frozen on the value it had when the page
/// mounted — a silent failure, and exactly the class this design is meant to
/// eliminate.
mixin HeaderPublisher<T extends StatefulWidget> on State<T> {
  /// Describe the header for this page. Called from [build]; read live state
  /// freely.
  HeaderSpec buildHeaderSpec();

  /// Call from [build]. Cheap and idempotent.
  void publishHeader() {
    final controller = HeaderScope.maybeReadOf(context);
    if (controller == null) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    // Published synchronously: writing the controller's map during build is
    // harmless, and the controller defers the resulting NOTIFICATION itself
    // (see HeaderController._notifySafely). Doing it here rather than in a
    // post-frame callback keeps the header one frame fresher.
    controller.publish(route, buildHeaderSpec());
  }
}
