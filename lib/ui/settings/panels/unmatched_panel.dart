import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/identified_episode.dart';
import '../../theme/xp_pressable.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/guarded.dart';
import '../../widgets/xp_message.dart';
import '../settings_actions.dart';

/// Settings › Unmatched: files that matched no show (kept on record across
/// rescans). Choosing one closes the window and opens fix-match for it.
///
/// This used to be a page of its own, pushed from the header; the walkthrough
/// asked for it to live with the other library upkeep, so it is a category
/// here and the header's Unmatched tab opens the window on it.
class UnmatchedPanel extends StatefulWidget {
  const UnmatchedPanel({super.key, required this.actions});

  final SettingsDialogActions actions;

  @override
  State<UnmatchedPanel> createState() => _UnmatchedPanelState();
}

class _UnmatchedPanelState extends State<UnmatchedPanel> {
  /// NULL only until the first load arrives; a later load assigns on arrival
  /// rather than clearing (never tear a list down to a spinner).
  List<IdentifiedEpisode>? _files;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    widget.actions.unmatchedCount.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.actions.unmatchedCount.removeListener(_reload);
    super.dispose();
  }

  void _reload() => fireAndForget(
    'unmatched list',
    () async {
      final f = await widget.actions.loadUnmatched();
      if (mounted) {
        setState(() {
          _files = f;
          _loadError = null;
        });
      }
    },
    // Information fails NEUTRAL: an error line, never an endless spinner and
    // never an empty list claiming there is nothing to fix.
    onError: (e) {
      if (mounted) setState(() => _loadError = e);
    },
  );

  void _fix(IdentifiedEpisode f) {
    // The window closes first: fix-match is a page, and it must not open
    // underneath a modal.
    Navigator.of(context).pop();
    unawaited(widget.actions.onFixMatch(f));
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    if (files == null) {
      if (_loadError != null) {
        return const XpMessage(
          "Couldn't read the unmatched list — details are in About.",
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (files.isEmpty) {
      return const XpMessage(
        'No unmatched files. Every scanned file matched a show.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Files that were scanned but matched nothing. They stay in the '
            'library and can be matched by hand; nothing is deleted or moved.',
            style: TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeCaption),
          ),
        ),
        if (_loadError != null)
          const Padding(
            padding: EdgeInsets.only(bottom: Xp.spaceS),
            child: Text(
              "Couldn't refresh this list — showing the last one read.",
              style: TextStyle(color: Xp.error, fontSize: Xp.fontSizeCaption),
            ),
          ),
        Expanded(child: _list(files)),
      ],
    );
  }

  Widget _list(List<IdentifiedEpisode> files) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 2),
    itemCount: files.length,
    itemBuilder: (_, i) {
      final f = files[i];
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: XpPressable(
          onTap: () => _fix(f),
          semanticsLabel: 'Fix match for ${f.fileName}',
          builder: (context, s) => Opacity(
            opacity: s.pressed ? 0.7 : 1,
            child: XpPanel(
              color: s.hovered || s.focused ? Xp.surfaceAlt : null,
              padding: const EdgeInsets.fromLTRB(
                Xp.spaceS + 2,
                Xp.spaceS,
                Xp.spaceS + 2,
                Xp.spaceS,
              ),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 18, color: Xp.textDim),
                  const SizedBox(width: Xp.spaceM),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ChromeLabel(
                          f.fileName,
                          upper: false,
                          fontSize: Xp.fontSizeLabel,
                          letterSpacing: 1,
                          maxLines: 2,
                        ),
                        const SizedBox(height: Xp.spaceXxs),
                        Text(
                          'parsed: "${f.parsedTitle}"'
                          '${f.parsedEpisodeNumber != null ? ' · ep ${f.parsedEpisodeNumber}' : ''}',
                          style: const TextStyle(
                            color: Xp.textDim,
                            fontSize: Xp.fontSizeCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Xp.spaceS),
                  const Icon(Icons.edit, size: 16, color: Xp.text),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
