import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// THE centered dim line: an empty list, a no-match search, a list that
/// could not be read. Six screens each centred a `Text` in `Xp.textDim`;
/// this is the one. [inset] puts it in the sunken well (an empty list's
/// place), [emphasis] sets it at title size (a whole page saying one thing).
class XpMessage extends StatelessWidget {
  const XpMessage(
    this.text, {
    super.key,
    this.inset = false,
    this.emphasis = false,
  });

  final String text;
  final bool inset;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final line = Center(
      child: Padding(
        padding: const EdgeInsets.all(Xp.spaceL),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Xp.textDim,
            fontSize: emphasis ? Xp.fontSizeTitle : Xp.fontSizeBody,
          ),
        ),
      ),
    );
    return inset ? XpPanel(inset: true, child: line) : line;
  }
}
