import 'package:flutter/material.dart';

import '../../../domain/models/source_descriptor.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/xp_dialog.dart';

/// Collects the client ID for a source that needs one.
///
/// **UNREACHABLE in the shipped app, on purpose.** No shipped source sets
/// `requiresClientId`, because both sources that would — MyAnimeList and Anime
/// Skip — are parked (`docs/multi-source-plan.md`). This is retained rather
/// than deleted because it is the whole cost of un-parking either one, and
/// `test/source_list_panel_test.dart` drives it through a synthetic descriptor
/// so it cannot rot while it waits. Do not remove it for having no caller.
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
  required SourceDescriptor source,
  String? current,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ClientIdDialog(source: source, current: current),
);

/// Stateful so the text controller has an owner that disposes it — this was
/// the one dialog in the app that leaked one.
class _ClientIdDialog extends StatefulWidget {
  const _ClientIdDialog({required this.source, required this.current});

  final SourceDescriptor source;
  final String? current;

  @override
  State<_ClientIdDialog> createState() => _ClientIdDialogState();
}

class _ClientIdDialogState extends State<_ClientIdDialog> {
  late final TextEditingController controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext dialogContext) {
    final source = widget.source;
    final current = widget.current;
    return XpDialog(
      title: '${source.displayName} client ID',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            source.setupInstructions ??
                'Paste the client ID for ${source.displayName}.',
            style: const TextStyle(
              color: Xp.textDim,
              fontSize: Xp.fontSizeBody,
            ),
          ),
          if (source.setupUrl != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              source.setupUrl!,
              style: const TextStyle(
                color: Xp.accent,
                fontSize: Xp.fontSizeBody,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'It stays on this machine and is never sent anywhere but that '
            'service.',
            style: TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeCaption),
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
              style: TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeCaption),
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
    );
  }
}
