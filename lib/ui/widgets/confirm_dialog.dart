import 'package:flutter/material.dart';

import '../theme/xp_widgets.dart';
import 'xp_dialog.dart';

/// THE yes/no question. Every action that destroys something the user cannot
/// get back — removing a folder, overwriting per-show choices, a reset — asks
/// through this, so the shape, the wording rules and the safe default are
/// decided once.
///
/// Returns true ONLY when [confirmLabel] was pressed. Escape, a click on the
/// barrier and [cancelLabel] all answer false: the way out that costs nothing
/// is always the easy one (CLAUDE.md: fail toward user-in-control). For the
/// same reason the CANCEL button is the lit one — the emphasis sits on the
/// choice that keeps things as they are, and the destructive verb is a plain
/// button the user has to mean.
///
/// [body] is finished copy: say exactly what will be lost and what is kept.
/// The dialog adds nothing to it.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => XpDialog(
      title: title,
      content: Text(body),
      actions: [
        XpButton(
          lit: true,
          label: cancelLabel,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        XpButton(
          label: confirmLabel,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return answer ?? false;
}
