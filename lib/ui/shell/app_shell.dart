import 'package:flutter/material.dart';

import '../theme/header_readout.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/header_actions.dart';
import 'header_controller.dart';
import 'header_scope.dart';
import 'header_spec.dart';

/// The ONE window chrome, mounted above the Navigator and never rebuilt by
/// navigation.
///
/// Every non-theater screen used to build its own `XpScreen` → `XpWindow` →
/// `XpTitleBar`, so pushing a route re-mounted the whole header and the default
/// page transition animated it along with the content — the header read as part
/// of the page rather than part of the app. Here the frame, the title bar and
/// the chassis are built once in `MaterialApp.builder`; the Navigator lives
/// INSIDE the chassis, so a route transition animates only content and the
/// header is genuinely out of every page's mount/rebuild cycle.
///
/// Pages no longer own header widgets — they publish a [HeaderSpec] (see
/// `HeaderPublisher`) and this reads it.
///
/// **Shape-invariant by construction.** The tree is always
/// `Scaffold > frame > Column[header slot, Expanded(chassis > content)]`. The
/// header slot collapses to zero height and the frame to zero width for a
/// [ChromelessPageRoute] (the theater, which draws its own header) — the
/// widgets change, the SHAPE does not. That matters because this sits above the
/// Navigator: a shape change here would re-parent it, rebuilding every route.
/// For the theater that means remounting `VideoZone` and restarting playback —
/// the Slice 2 failure. Any future change here must preserve the shape.
/// **Why the Overlay.** Sitting above the Navigator means sitting above the
/// Navigator's Overlay too, and the header's tooltips need one ("No Overlay
/// widget found"). The shell therefore hosts its own, created ONCE from
/// `initialEntries` so it is never rebuilt structurally; the whole shell —
/// header and content — renders inside that single entry.
///
/// **Why the controller is passed in, not read from [HeaderScope].** The header
/// renders inside that OverlayEntry, and an entry's builder runs in its own
/// element subtree. Depending on an InheritedWidget across that boundary proved
/// unreliable: the first publish did not repaint the header, and the title only
/// appeared once a window RESIZE happened to rebuild the entry through its
/// unrelated MediaQuery dependency — a stale header until the user shook the
/// window. The chrome collapse for the theater was late for the same reason.
/// So the shell now subscribes EXPLICITLY, with a [ListenableBuilder]. Same
/// data, but the rebuild is guaranteed rather than inferred. [HeaderScope]
/// remains, purely so PAGES can find the controller to publish to.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.child});

  /// The header state. Subscribed to directly — see the class doc.
  final HeaderController controller;

  /// The Navigator, from `MaterialApp.builder`.
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final OverlayEntry _entry = OverlayEntry(builder: _buildShell);

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The entry closes over `widget`, so a new child (a rebuilt Navigator) has
    // to be pushed into it explicitly.
    if (widget.child != oldWidget.child) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);

  Widget _buildShell(BuildContext context) => ListenableBuilder(
    // EXPLICIT subscription — the guarantee the inherited read could not give
    // across the Overlay boundary. Every publish and every route change
    // repaints the header, including the very first one.
    listenable: widget.controller,
    builder: (context, _) => _chrome(context, widget.controller),
  );

  Widget _chrome(BuildContext context, HeaderController header) {
    final chrome = header.chromeVisible;

    return Scaffold(
      // The ONE Scaffold for the shell pages. Snackbars therefore surface here,
      // app-level, instead of dying with the page that raised them.
      backgroundColor: Xp.desktop,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: chrome ? Xp.frameBlue : Colors.transparent,
          borderRadius: chrome
              ? const BorderRadius.vertical(
                  top: Radius.circular(Xp.windowRadius),
                )
              : BorderRadius.zero,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            chrome ? Xp.frameWidth : 0,
            0,
            chrome ? Xp.frameWidth : 0,
            chrome ? Xp.frameWidth : 0,
          ),
          child: ClipRRect(
            borderRadius: chrome
                ? const BorderRadius.vertical(
                    top: Radius.circular(Xp.windowRadius),
                  )
                : BorderRadius.zero,
            child: Column(
              children: [
                // Fixed slot: zero-height when chromeless, never removed.
                SizedBox(
                  height: chrome ? Xp.titleBarHeight : 0,
                  child: chrome
                      ? _TitleBar(header: header)
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: XpChassis(
                    color: chrome ? Xp.frame : Xp.desktop,
                    child: _ContentRegion(child: widget.child),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where page content lives inside the chassis.
///
/// A [Stack] with the Navigator as its only child today. That is deliberate and
/// is the seam for the persistent video layer: a mini-player becomes a SECOND
/// Stack child positioned from app state, and nothing here assumes the
/// Navigator fills the chassis. Costs nothing now and means that seam is opened
/// once rather than twice. (The layer itself is NOT built — see
/// docs/player-architecture-research.md §6, Slice 3.)
class _ContentRegion extends StatelessWidget {
  const _ContentRegion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Stack(children: [Positioned.fill(child: child)]);
}

/// The header bar, fed entirely from [HeaderController].
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.header});

  final HeaderController header;

  @override
  Widget build(BuildContext context) {
    final showLabel = XpTitleBar.showsLabels(context);
    // BACK COMES FROM THE NAVIGATOR, not from the spec — a missing or stale
    // spec can never remove the way back. When there's nothing to pop the slot
    // is still reserved at full width, which is what keeps the centred readout
    // from shifting between home and a pushed page.
    final back = XpTitleTab(
      icon: Icons.arrow_back,
      label: 'Back',
      tooltip: 'Back',
      showLabel: showLabel,
      onPressed: header.pop,
    );

    return XpTitleBar(
      caption: header.title ?? '',
      captionWidget: HeaderReadout(
        title: header.title,
        spinning: header.spinning,
      ),
      leading: header.canPop
          ? back
          : Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: back,
            ),
      trailing: _actions(header.actions, showLabel),
    );
  }

  /// Build the trailing cluster from DATA. [NoActions] renders nothing — the
  /// fail state for anything with a side effect.
  Widget? _actions(HeaderActions actions, bool showLabel) => switch (actions) {
    NoActions() => null,
    SingleAction(:final icon, :final label, :final tooltip, :final onPressed) =>
      XpTitleTab(
        icon: icon,
        label: label,
        tooltip: tooltip,
        showLabel: showLabel,
        onPressed: onPressed,
      ),
    AppActions(
      :final scanning,
      :final unmatchedCount,
      :final onFolders,
      :final onScan,
      :final onUnmatched,
      :final onSettings,
    ) =>
      HeaderActionsBar(
        scanning: scanning,
        unmatchedCount: unmatchedCount,
        onFolders: onFolders,
        onScan: onScan,
        onUnmatched: onUnmatched,
        onSettings: onSettings,
      ),
  };
}
