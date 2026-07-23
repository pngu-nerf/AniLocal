import 'package:flutter/material.dart';

import '../theme/header_readout.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// The SHARED screen shell in the instrument chrome — one shell for every
/// non-theater screen (home, detail, Sources, Unmatched, Fix-match), so their
/// headers can't drift. Composes the existing [XpWindow] with the VFD
/// [HeaderReadout] caption, an optional VFD back tab ([showBack]), and optional
/// [trailing] header content (a [HeaderActionsBar] on home/detail, an "Add" tab
/// on Sources, nothing elsewhere). Callers supply only [child] — no bespoke
/// per-page chrome. (The theater deliberately does NOT use this: its shell is
/// entangled with the fullscreen/player machinery — see docs/header-architecture
/// -audit.md.)
class XpScreen extends StatelessWidget {
  const XpScreen({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showBack = true,
  });

  /// The header readout word after "AniLocal" (e.g. "Sources").
  final String title;
  final Widget child;

  /// Optional header content at the top-right (e.g. a [HeaderActionsBar] or an
  /// "Add" tab).
  final Widget? trailing;

  /// Whether to show the VFD back tab. False for the root route (home), which
  /// has nothing to pop; true (default) for pushed screens.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    // Match HeaderActionsBar's threshold so the back tab collapses to an icon at
    // the same width as the action tabs.
    final showLabel = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      backgroundColor: Xp.desktop,
      body: XpWindow(
        caption: title,
        captionWidget: HeaderReadout(title: title),
        titleLeading: showBack
            ? XpTitleTab(
                icon: Icons.arrow_back,
                label: 'Back',
                tooltip: 'Back',
                showLabel: showLabel,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        titleTrailing: trailing,
        child: child,
      ),
    );
  }
}
