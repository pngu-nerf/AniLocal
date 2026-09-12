import 'dart:async';

import 'package:flutter/material.dart';

import '../diagnostics/app_log.dart';
import '../domain/models/identified_episode.dart';
import 'library_services.dart';
import 'routes.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'theme/xp_pressable.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';

/// Lists files that matched no show (kept on record across rescans). Tapping
/// one opens fix-match to assign it (the OPM Specials case).
class UnmatchedScreen extends StatefulWidget {
  const UnmatchedScreen({super.key, required this.services});

  final LibraryServices services;

  @override
  State<UnmatchedScreen> createState() => _UnmatchedScreenState();
}

class _UnmatchedScreenState extends State<UnmatchedScreen>
    with HeaderPublisher {
  /// NULL only until the first load arrives. A re-scan after a fix-match
  /// assigns the new list on arrival rather than clearing this, so the list
  /// isn't torn down to a spinner and back. See CLAUDE.md, "never clear known
  /// content to show a loading state".
  List<IdentifiedEpisode>? _files;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    unawaited(
      widget.services.repository.unmatchedFiles().then(
        (f) {
          if (mounted) setState(() => _files = f);
        },
        // Information fails NEUTRAL: an error line, not a spinner that never
        // ends and not an empty list claiming there is nothing to fix.
        onError: (Object e, StackTrace stack) {
          AppLog.error('Unmatched list failed', error: e, stack: stack);
          if (mounted) setState(() => _loadError = e);
        },
      ),
    );
  }

  Future<void> _fix(IdentifiedEpisode f) async {
    final done = await AppRoutes.fixMatch(
      context,
      services: widget.services,
      filePaths: [f.filePath],
      prefillQuery: f.parsedTitle,
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    publishHeader();
    final files = _files;
    // Spinner ONLY before the first load has ever arrived.
    if (files == null) {
      final error = _loadError;
      if (error != null) {
        return const Center(
          child: Text(
            "Couldn't read the unmatched list — details are in "
            'Settings › About.',
            style: TextStyle(color: Xp.textDim),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (files.isEmpty) {
      return const Center(
        child: Text('No unmatched files.', style: TextStyle(color: Xp.textDim)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: files.length,
      itemBuilder: (_, i) {
        final f = files[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(Xp.spaceS, 3, Xp.spaceS, 3),
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

  @override
  HeaderSpec buildHeaderSpec() => const HeaderSpec(title: 'Unmatched files');
}
