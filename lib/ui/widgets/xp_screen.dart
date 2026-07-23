import 'package:flutter/material.dart';

import '../theme/header_readout.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// A pushed full-screen page in the instrument chrome — the SHARED shell for the
/// secondary flows (Sources / Unmatched / Fix-match), so they match home /
/// detail / player. Composes the existing [XpWindow] with the VFD [HeaderReadout]
/// caption and a VFD back tab; [trailing] takes optional header actions (as
/// [XpTitleTab]s). Callers supply only [child] — no bespoke per-page chrome.
class XpScreen extends StatelessWidget {
  const XpScreen({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  /// The header readout word after "AniLocal" (e.g. "Sources").
  final String title;
  final Widget child;

  /// Optional header action(s) at the top-right (e.g. an "Add" tab).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Match HeaderActionsBar's threshold so the back tab collapses to an icon at
    // the same width as the home/detail headers.
    final showLabel = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      backgroundColor: Xp.desktop,
      body: XpWindow(
        caption: title,
        captionWidget: HeaderReadout(title: title),
        titleLeading: XpTitleTab(
          icon: Icons.arrow_back,
          label: 'Back',
          tooltip: 'Back',
          showLabel: showLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleTrailing: trailing,
        child: child,
      ),
    );
  }
}
