import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// The ONE dialog shell for the whole app: the same blue window-frame + chassis
/// title bar as [XpWindow], the content on the chassis, and a trailing actions
/// row (pass [XpButton]s). Every `showDialog` routes through this so dialogs are
/// consistent and new ones get the instrument look for free.
///
/// Use inside showDialog, e.g.
/// `showDialog(builder: (_) => XpDialog(title: 'Settings', content: …))`.
class XpDialog extends StatelessWidget {
  const XpDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.maxWidth = 460,
  });

  final String title;
  final Widget content;

  /// Trailing action buttons (typically [XpButton]s), laid out right-aligned.
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(Xp.windowRadius));
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          // The blue window frame — shows as a slim border around the chassis.
          decoration: const BoxDecoration(
            color: Xp.frameBlue,
            borderRadius: radius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Xp.frameWidth),
            child: ClipRRect(
              borderRadius: radius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _titleBar(),
                  // Content on the chassis; Flexible so a tall body (a caller's
                  // SingleChildScrollView) scrolls instead of overflowing.
                  Flexible(
                    child: ColoredBox(
                      color: Xp.frame,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: content,
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty)
                    ColoredBox(
                      color: Xp.frame,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              actions[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The chassis title strip: the same gradient + lit sheen as the window title
  /// bar, with a chrome-label caption. No traffic-light inset / drag area (this
  /// is a floating dialog, not the app window).
  Widget _titleBar() => DecoratedBox(
    decoration: const BoxDecoration(gradient: Xp.titleGradient),
    child: Column(
      children: [
        const ColoredBox(
          color: Xp.titleGloss,
          child: SizedBox(height: 1, width: double.infinity),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChromeLabel(
              title,
              color: Xp.textOnTitle,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}
