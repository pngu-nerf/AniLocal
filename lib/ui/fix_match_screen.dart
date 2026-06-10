import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSplit ? 'Reassign $count files' : 'Fix match'),
      ),
      body: Column(
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
                IconButton.filled(
                  icon: const Icon(Icons.search),
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
          const Divider(height: 1),
          Expanded(child: _candidates()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: (_selected == null || _busy) ? null : _assign,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_selected == null ? 'Pick a match' : 'Assign'),
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
          return const Center(child: Text('Search for the correct title.'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Search failed: ${snapshot.error}'));
        }
        final results = snapshot.data ?? const [];
        if (results.isEmpty) {
          return const Center(child: Text('No candidates.'));
        }
        return ListView(
          children: [
            for (final s in results)
              ListTile(
                selected: _selected?.anilistId == s.anilistId,
                onTap: () => setState(() => _selected = s),
                leading: s.coverImageRef != null && _isLocal(s.coverImageRef!)
                    ? Image.file(File(s.coverImageRef!), width: 40)
                    : const Icon(Icons.image_outlined),
                title: Text(
                  s.titles.english ??
                      s.titles.romaji ??
                      s.titles.native ??
                      '#${s.anilistId}',
                ),
                subtitle: Text(
                  [
                    if (s.format != null) s.format,
                    if (s.episodeCount != null) '${s.episodeCount} ep',
                    'AniList #${s.anilistId}',
                  ].join(' · '),
                ),
                trailing: _selected?.anilistId == s.anilistId
                    ? const Icon(Icons.check_circle)
                    : null,
              ),
          ],
        );
      },
    );
  }

  bool _isLocal(String ref) => !ref.startsWith('http');
}
