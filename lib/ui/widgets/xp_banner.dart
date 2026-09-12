import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// An in-page notice: an icon, one line of copy, and its actions, on the
/// chassis. THE banner — the two access-recovery banners were Material
/// `MaterialBanner`s with `TextButton`s (the only ones in the app, sitting on
/// an all-chassis page) and the show page carried a third implementation.
class XpBanner extends StatelessWidget {
  const XpBanner({
    super.key,
    required this.icon,
    required this.message,
    this.iconColor = Xp.warning,
    this.actions = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String message;

  /// Buttons, right-aligned; normally [XpButton]s.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Xp.spaceL, Xp.spaceM, Xp.spaceL, 0),
    child: XpPanel(
      color: Xp.surfaceAlt,
      padding: const EdgeInsets.symmetric(
        horizontal: Xp.spaceS,
        vertical: Xp.spaceXs,
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: Xp.spaceXs),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Xp.text, fontSize: Xp.fontSizeBody),
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: Xp.spaceXs), a],
        ],
      ),
    ),
  );
}
