import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// THE error state: the instrument's sunken display well holding an optional
/// icon, a headline, an optional line of detail, any extra lines, and the
/// actions. The show page, the library and the player each drew their own
/// (icon vs none, warning vs error colour, three paddings, two max widths);
/// this is the one shape. Opaque, so it reads the same over the chassis, a
/// black frame and a frozen picture.
class XpErrorState extends StatelessWidget {
  const XpErrorState({
    super.key,
    required this.headline,
    this.message,
    this.icon,
    this.severe = false,
    this.extra = const [],
    this.actions = const [],
    this.maxWidth = Xp.measureBody,
  });

  final String headline;
  final String? message;

  /// A leading icon, in the warning colour — the show page's idiom.
  final IconData? icon;

  /// The headline in the failure colour: a loss, not a hiccup.
  final bool severe;

  /// Further lines between the message and the actions (a path, a hint).
  final List<Widget> extra;

  /// Normally [XpButton]s; laid out in a wrapping row.
  final List<Widget> actions;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    const dim = TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeBody);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: XpPanel(
          inset: true,
          padding: const EdgeInsets.all(Xp.spaceL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Xp.warning, size: 32),
                const SizedBox(height: Xp.spaceS),
              ],
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: severe ? Xp.error : Xp.text,
                  fontSize: Xp.fontSizeTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message case final m?) ...[
                const SizedBox(height: Xp.spaceS),
                Text(
                  m,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: dim,
                ),
              ],
              for (final line in extra) ...[
                const SizedBox(height: Xp.spaceXs),
                DefaultTextStyle.merge(
                  style: dim,
                  textAlign: TextAlign.center,
                  child: line,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Xp.spaceM),
                Wrap(
                  spacing: Xp.spaceS,
                  runSpacing: Xp.spaceS,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
