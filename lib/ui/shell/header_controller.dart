import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'header_spec.dart';

/// Tracks which page is on top and what header it wants — the state behind the
/// ONE hoisted header.
///
/// **Route-keyed, so pop-restore is structural.** Specs live in a map keyed by
/// the publishing page's route, and the effective spec is simply
/// `_specs[_top]`. Popping B therefore reveals A's spec because A's entry was
/// never removed — no page has to remember to re-publish on the way back, and
/// there is no `didPopNext` to forget. The alternative (a single current-value
/// notifier that each page rewrites) fails silently the moment one page skips
/// the restore.
///
/// **Only [PageRoute]s count.** The observer is typed to `PageRoute`, so
/// dialogs and popup menus — which are routes on the same navigator — never
/// become "the top page". Without that filter, opening the Settings dialog
/// would make the top route a spec-less one and spin the readout behind it.
class HeaderController extends ChangeNotifier {
  HeaderController({required this.navigatorKey});

  /// The navigator whose stack this header describes. Also the source of truth
  /// for the back button — see [canPop].
  final GlobalKey<NavigatorState> navigatorKey;

  /// How long the readout stays BLANK before falling to the spinner.
  ///
  /// Navigation legitimately produces a sub-frame gap where the outgoing page's
  /// spec is gone and the incoming page hasn't published yet. Spinning
  /// instantly would flash on every push. Blank is invisible for that long, so
  /// the spinner is reserved for genuinely having nothing to show.
  static const Duration spinnerGrace = Duration(milliseconds: 200);

  final Map<Route<dynamic>, HeaderSpec> _specs = {};
  Route<dynamic>? _top;
  Timer? _graceTimer;
  bool _spinning = false;

  /// The top page's spec, or null if it hasn't published (or opted out).
  HeaderSpec? get spec => _top == null ? null : _specs[_top];

  /// The readout's context line, or null when there is nothing valid to show.
  String? get title => spec?.title;

  /// Whether the readout should show its seeking spinner. True only after
  /// [spinnerGrace] has elapsed with no valid title.
  bool get spinning => _spinning;

  /// Trailing actions. Absent when the spec is missing — actions FAIL ABSENT,
  /// because a stale action still fires its side effect.
  HeaderActions get actions => spec?.actions ?? const NoActions();

  /// Whether the header should draw chrome at all. False for routes that own
  /// their own (the theater) — see [ChromelessPageRoute].
  bool get chromeVisible => _top is! ChromelessPageRoute;

  /// GROUND TRUTH for the back button — the navigator itself, never a spec.
  /// If the navigator can't be reached, this answers TRUE: an inert back button
  /// is a mild oddity, a missing one is a dead end.
  bool get canPop => navigatorKey.currentState?.canPop() ?? true;

  void pop() => navigatorKey.currentState?.maybePop();

  /// Called by a page for its OWN route, on first build and every rebuild.
  /// Equal specs are dropped, so republishing every frame is free.
  void publish(Route<dynamic> route, HeaderSpec next) {
    if (_specs[route] == next) return;
    _specs[route] = next;
    if (route == _top) _onContentChanged();
  }

  // --- navigator observation ------------------------------------------------

  void onTopChanged(Route<dynamic>? top) {
    if (_top == top) return;
    _top = top;
    _onContentChanged();
  }

  void onRouteGone(Route<dynamic> route) {
    _specs.remove(route); // don't leak specs for dead routes
  }

  /// Notify listeners, deferring to after the frame if we're inside one.
  ///
  /// Both entry points can fire mid-build: pages publish FROM `build`, and the
  /// navigator's first `didPush` happens while the Navigator itself is
  /// building. Mutating our own state then is harmless; marking the HeaderScope
  /// dirty is not ("setState() called during build"). Coalesced, so a burst of
  /// publishes in one frame produces a single rebuild.
  bool _notifyScheduled = false;

  void _notifySafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    if (!midFrame) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// Restart the grace clock whenever what we'd display changes.
  void _onContentChanged() {
    _graceTimer?.cancel();
    if (title != null || !chromeVisible) {
      // Valid content — or no readout on screen at all (a chromeless route like
      // the theater). Either way there is nothing to spin, so don't arm a timer
      // that would tick away behind the player for no reason.
      _spinning = false;
    } else if (!_spinning) {
      _graceTimer = Timer(spinnerGrace, () {
        if (title == null) {
          _spinning = true;
          _notifySafely();
        }
      });
    }
    _notifySafely();
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }
}

/// A route that draws its OWN chrome, so the shell collapses for it.
///
/// The theater is pushed with this. It lives on the same navigator as the five
/// shell pages, so without an opt-out the shell would render its header above
/// the theater's — two headers. Marking the ROUTE (rather than having the
/// theater publish an opt-out from `initState`) means the shell knows before
/// the first frame, so no chrome ever flashes over the player.
///
/// A type, not a magic string in `RouteSettings.name`, so a rename can't
/// silently reconnect the header.
class ChromelessPageRoute<T> extends MaterialPageRoute<T> {
  ChromelessPageRoute({required super.builder, super.settings});
}

/// Feeds [HeaderController] from the navigator. Typed to [PageRoute] so dialogs
/// and popups are ignored — see the controller's doc.
class HeaderRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  HeaderRouteObserver(this.controller);

  final HeaderController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) controller.onTopChanged(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) {
      controller.onRouteGone(route);
      controller.onTopChanged(previousRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute) {
      controller.onRouteGone(route);
      controller.onTopChanged(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) controller.onRouteGone(oldRoute);
    if (newRoute is PageRoute) controller.onTopChanged(newRoute);
  }
}
