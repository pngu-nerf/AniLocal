import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import 'fix_match_screen.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/xp_screen.dart';

/// Lists files that matched no AniList entry (kept on record across rescans).
/// Tapping one opens fix-match to assign it (the OPM Specials case).
class UnmatchedScreen extends StatefulWidget {
  const UnmatchedScreen({
    super.key,
    required this.repository,
    required this.fixMatch,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;

  @override
  State<UnmatchedScreen> createState() => _UnmatchedScreenState();
}

class _UnmatchedScreenState extends State<UnmatchedScreen> {
  late Future<List<IdentifiedEpisode>> _files;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _files = widget.repository.unmatchedFiles();
    });
  }

  Future<void> _fix(IdentifiedEpisode f) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: [f.filePath],
          prefillQuery: f.parsedTitle,
        ),
      ),
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return XpScreen(
      title: 'Unmatched files',
      child: FutureBuilder<List<IdentifiedEpisode>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data ?? const [];
          if (files.isEmpty) {
            return const Center(
              child: Text(
                'No unmatched files.',
                style: TextStyle(color: Xp.textDim),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: files.length,
            itemBuilder: (_, i) {
              final f = files[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                child: _Tappable(
                  onTap: () => _fix(f),
                  child: XpPanel(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.help_outline,
                          size: 18,
                          color: Xp.textDim,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ChromeLabel(
                                f.fileName,
                                upper: false,
                                fontSize: 13,
                                letterSpacing: 1,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'parsed: "${f.parsedTitle}"'
                                '${f.parsedEpisodeNumber != null ? ' · ep ${f.parsedEpisodeNumber}' : ''}',
                                style: const TextStyle(
                                  color: Xp.textDim,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit, size: 16, color: Xp.text),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A press-feedback wrapper (mirrors the detail list's tappable rows) so a whole
/// row reads as a button without a Material [InkWell] ripple on the chassis.
class _Tappable extends StatefulWidget {
  const _Tappable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: Opacity(opacity: _down ? 0.7 : 1, child: widget.child),
      ),
    );
  }
}
