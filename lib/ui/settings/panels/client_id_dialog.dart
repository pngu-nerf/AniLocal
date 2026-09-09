import 'package:flutter/material.dart';

import '../../../domain/models/metadata_source.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/xp_dialog.dart';

/// Collects the client ID for a source that needs one.
///
/// Returns the entered value, `''` to clear a stored key, or null when the user
/// cancelled — cancel must leave an existing key untouched, which a plain empty
/// string could not express.
///
/// The value is a client ID: it identifies an APPLICATION, not a person, and
/// grants no access to anyone's account. It is not masked for that reason —
/// hiding it would imply a secrecy it doesn't have and make typos unfindable.
Future<String?> showClientIdDialog(
  BuildContext context, {
  required MetadataSource source,
  String? current,
}) {
  final controller = TextEditingController(text: current ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => XpDialog(
      title: '${source.displayName} client ID',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            source.setupInstructions ??
                'Paste the client ID for ${source.displayName}.',
            style: const TextStyle(color: Xp.textDim, fontSize: 12),
          ),
          if (source.setupUrl != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              source.setupUrl!,
              style: const TextStyle(color: Xp.accent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'It stays on this machine and is never sent anywhere but that '
            'service.',
            style: TextStyle(color: Xp.textDim, fontSize: 11),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Client ID',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          ),
          if ((current ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Clearing the field removes the key and disables the source.',
              style: TextStyle(color: Xp.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
      actions: [
        XpButton(
          dense: true,
          label: 'Cancel',
          // Null, not '': cancelling must not wipe a stored key.
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        XpButton(
          dense: true,
          label: 'Save',
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
        ),
      ],
    ),
  );
}
