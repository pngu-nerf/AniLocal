import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/xp_screen.dart';

/// Minimal manual fix-match: search AniList → pick from ranked candidates →
/// assign. For a split (multiple files), an optional toggle chooses continuous
/// vs AniList-faithful display numbering. Pops `true` when an override is set.
class FixMatchScreen extends StatefulWidget {
  const FixMatchScreen({
    super.key,
    required this.fixMatch,
    required this.filePaths,
    required this.prefillQuery,
    this.isSplit = false,
    this.priorEpisodeCount = 0,
  });

  final FixMatchRepository fixMatch;

  /// One path = assign/reassign a single file; many (ordered) = a split range.
  final List<String> filePaths;
  final String prefillQuery;
  final bool isSplit;

  /// Real prior-season episode count, for continuous display (anchored + this).
  final int priorEpisodeCount;

  @override
  State<FixMatchScreen> createState() => _FixMatchScreenState();
}

class _FixMatchScreenState extends State<FixMatchScreen> {
  late final TextEditingController _query = TextEditingController(
    text: widget.prefillQuery,
  );
  Future<List<Series>>? _results;
  Series? _selected;
  bool _continuous = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _selected = null;
      _results = widget.fixMatch.searchCandidates(_query.text.trim());
    });
  }

  Future<void> _assign() async {
    final chosen = _selected;
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      if (widget.isSplit && widget.filePaths.length > 1) {
        await widget.fixMatch.assignRange(
          filePaths: widget.filePaths,
          chosen: chosen,
          anchorStart: 1,
          continuousOffset: _continuous ? widget.priorEpisodeCount : 0,
          displayContinuous: _continuous,
        );
      } else {
        await widget.fixMatch.assignFile(
          filePath: widget.filePaths.first,
          chosen: chosen,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Assign failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.filePaths.length;
    return XpScreen(
      title: widget.isSplit ? 'Reassign $count files' : 'Fix match',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'Search AniList',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                XpButton(
                  icon: Icons.search,
                  tooltip: 'Search',
                  onPressed: _search,
                ),
              ],
            ),
          ),
          if (widget.isSplit && count > 1)
            SwitchListTile(
              value: _continuous,
              onChanged: (v) => setState(() => _continuous = v),
              title: const Text('Continuous numbering'),
              subtitle: Text(
                _continuous
                    ? 'Show ${widget.priorEpisodeCount + 1}, ${widget.priorEpisodeCount + 2}… '
                          '(prior season had ${widget.priorEpisodeCount})'
                    : 'Show AniList episodes 1, 2, 3…',
              ),
            ),
          const Divider(height: 1, color: Xp.divider),
          Expanded(child: _candidates()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: XpButton(
                lit: _selected != null && !_busy,
                label: _busy
                    ? 'Assigning…'
                    : (_selected == null ? 'Pick a match' : 'Assign'),
                onPressed: (_selected == null || _busy) ? null : _assign,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidates() {
    return FutureBuilder<List<Series>>(
      future: _results,
      builder: (context, snapshot) {
        if (_results == null) {
          return const _CandidatesMessage('Search for the correct title.');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CandidatesMessage('Search failed: ${snapshot.error}');
        }
        final results = snapshot.data ?? const [];
        if (results.isEmpty) {
          return const _CandidatesMessage('No candidates.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: results.length,
          itemBuilder: (_, i) {
            final s = results[i];
            final selected = _selected?.anilistId == s.anilistId;
            final title = s.displayTitle;
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = s),
                  child: XpPanel(
                    // Selection is shown by lighting the panel face (dim cyan).
                    color: selected ? Xp.accentDeep : null,
                    padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 52,
                          child:
                              s.coverImageRef != null &&
                                  _isLocal(s.coverImageRef!)
                              ? Image.file(
                                  File(s.coverImageRef!),
                                  fit: BoxFit.cover,
                                )
                              : const ColoredBox(
                                  color: Xp.well,
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: Xp.textFaint,
                                    size: 18,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ChromeLabel(
                                title,
                                upper: false,
                                fontSize: 13,
                                letterSpacing: 1,
                                maxLines: 2,
                                color: selected ? Xp.accentBright : Xp.text,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (s.format != null) s.format,
                                  if (s.episodeCount != null)
                                    '${s.episodeCount} ep',
                                  'AniList #${s.anilistId}',
                                ].join(' · '),
                                style: const TextStyle(
                                  color: Xp.textDim,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle,
                            size: 18,
                            color: Xp.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _isLocal(String ref) => !ref.startsWith('http');
}

/// Centered dim message for the candidates area's empty / prompt / error states.
class _CandidatesMessage extends StatelessWidget {
  const _CandidatesMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Xp.textDim),
      ),
    ),
  );
}
