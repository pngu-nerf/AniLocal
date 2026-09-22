import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diagnostics/app_log.dart';
import '../domain/models/series.dart';
import '../domain/paths.dart' show basenameOf;
import '../domain/repositories/fix_match_repository.dart';
import 'library/library_search_bar.dart';
import 'metadata_failure_message.dart';
import 'settings/setting_row.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'theme/xp_pressable.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/notices.dart';

/// Manual fix-match: search the metadata sources → pick from ranked candidates
/// → assign. For a split (multiple files), a toggle chooses continuous vs
/// source-faithful display numbering. Pops `true` when an override is set.
class FixMatchScreen extends StatefulWidget {
  const FixMatchScreen({
    super.key,
    required this.fixMatch,
    required this.filePaths,
    required this.prefillQuery,
    this.isSplit = false,
    this.priorEpisodeCount = 0,
    this.scanning,
  });

  final FixMatchRepository fixMatch;

  /// True while a scan runs. Assign is disabled then: the scan is rewriting
  /// the same file rows, and an override written under it could bind to a
  /// row the next batch replaces. Null (tests) means never scanning.
  final ValueListenable<bool>? scanning;

  /// One path = assign/reassign a single file; many (ordered) = a split range.
  final List<String> filePaths;
  final String prefillQuery;
  final bool isSplit;

  /// Real prior-season episode count, for continuous display (anchored + this).
  final int priorEpisodeCount;

  @override
  State<FixMatchScreen> createState() => _FixMatchScreenState();
}

/// The stand-in listenable when no scan state is wired (tests).
final ValueNotifier<bool> _never = ValueNotifier<bool>(false);

class _FixMatchScreenState extends State<FixMatchScreen> with HeaderPublisher {
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
    _query.addListener(_onQueryChanged);
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The Search button follows the field: disabled while it is blank, so a
  /// press with nothing typed cannot silently do nothing.
  void _onQueryChanged() => setState(() {});

  bool get _canSearch => _query.text.trim().isNotEmpty;

  void _search() {
    if (!_canSearch) return;
    final future = widget.fixMatch.searchCandidates(_query.text.trim());
    // Logged ONCE, here, where the future is created — not inside `build`,
    // where a failed search re-logged itself on every rebuild and flooded the
    // diagnostics ring.
    unawaited(
      future.then(
        (_) {},
        onError: (Object e, StackTrace stack) =>
            AppLog.error('Fix-match search failed', error: e, stack: stack),
      ),
    );
    setState(() {
      _selected = null;
      _results = future;
    });
  }

  Future<void> _assign() async {
    final chosen = _selected;
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      // The override is keyed by the file's fingerprint; a file that has gone
      // since the list was read would pin a phantom. Check before writing.
      for (final p in widget.filePaths) {
        if (!await File(p).exists()) {
          throw StateError(
            "The file isn't there any more (${basenameOf(p)}). "
            'Scan to update the list, then try again.',
          );
        }
      }
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
    } catch (e, stack) {
      AppLog.error('Fix-match assign failed', error: e, stack: stack);
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, "Couldn't assign.", e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.filePaths.length;
    publishHeader();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Xp.spaceL),
          child: Row(
            children: [
              Expanded(
                // The SAME search field the library and the show page use.
                child: LibrarySearchBar(
                  controller: _query,
                  hintText: 'Search for the show',
                  onChanged: (_) {},
                  onClear: _query.clear,
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: Xp.spaceS),
              XpButton(
                icon: Icons.search,
                tooltip: 'Search',
                onPressed: _canSearch ? _search : null,
              ),
            ],
          ),
        ),
        if (widget.isSplit && count > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Xp.spaceL),
            child: SettingRow(
              label: 'Continuous numbering',
              subtitle: _continuous
                  ? 'Show ${widget.priorEpisodeCount + 1}, '
                        '${widget.priorEpisodeCount + 2}… (the prior season '
                        'had ${widget.priorEpisodeCount})'
                  : 'Show episodes 1, 2, 3… as the source numbers them',
              control: SettingSwitch(
                value: _continuous,
                onChanged: (v) => setState(() => _continuous = v),
              ),
            ),
          ),
        const Divider(height: 1, color: Xp.divider),
        Expanded(child: _candidates()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Xp.spaceL),
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.scanning ?? _never,
              builder: (context, scanning, _) => XpButton(
                lit: _selected != null && !_busy && !scanning,
                // One label. The instruction ("pick a match") lives in the
                // candidate pane's empty state, not on a button that renamed
                // itself whenever it could not be pressed.
                label: _busy ? 'Assigning…' : 'Assign',
                tooltip: scanning ? 'Wait for the scan to finish' : null,
                onPressed: (_selected == null || _busy || scanning)
                    ? null
                    : _assign,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  HeaderSpec buildHeaderSpec() {
    final count = widget.filePaths.length;
    return HeaderSpec(
      title: widget.isSplit ? 'Reassign $count files' : 'Fix match',
    );
  }

  Widget _candidates() {
    return FutureBuilder<List<Series>>(
      future: _results,
      builder: (context, snapshot) {
        if (_results == null) {
          return const _CandidatesMessage(
            'Search for the correct title, then pick a match.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CandidatesMessage(
            'Search failed. ${userFacingMessage(snapshot.error!)}',
          );
        }
        final results = snapshot.data ?? const [];
        if (results.isEmpty) {
          return const _CandidatesMessage('No candidates.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: results.length,
          itemBuilder: (_, i) => _CandidateRow(
            series: results[i],
            selected: _selected?.seriesId == results[i].seriesId,
            onTap: () => setState(() => _selected = results[i]),
          ),
        );
      },
    );
  }
}

/// One ranked candidate. Its cover comes straight from the provider — a
/// REMOTE URL — so it is fetched, not read from disk: the old `_isLocal` test
/// treated every provider URL as not-local and drew the placeholder for every
/// candidate, always.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.series,
    required this.selected,
    required this.onTap,
  });

  final Series series;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = series;
    final title = s.displayTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Xp.spaceS, 3, Xp.spaceS, 3),
      child: XpPressable(
        onTap: onTap,
        semanticsLabel: title,
        builder: (context, state) => XpPanel(
          // Selection is shown by lighting the panel face (dim cyan).
          color: selected
              ? Xp.accentDeep
              : (state.hovered || state.focused ? Xp.surfaceAlt : null),
          padding: const EdgeInsets.fromLTRB(Xp.spaceS, 6, Xp.spaceS + 2, 6),
          child: Row(
            children: [
              SizedBox(width: 36, height: 52, child: _cover(s.coverImageRef)),
              const SizedBox(width: Xp.spaceM),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChromeLabel(
                      title,
                      upper: false,
                      fontSize: Xp.fontSizeLabel,
                      letterSpacing: 1,
                      maxLines: 2,
                      color: selected ? Xp.accentBright : Xp.text,
                    ),
                    const SizedBox(height: Xp.spaceXxs),
                    Text(
                      [
                        if (s.format != null) s.format,
                        if (s.episodeCount != null) '${s.episodeCount} ep',
                        if (s.externalIds.anilist != null)
                          'AniList #${s.externalIds.anilist}',
                      ].join(' · '),
                      style: const TextStyle(
                        color: Xp.textDim,
                        fontSize: Xp.fontSizeCaption,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: Xp.spaceS),
                const Icon(Icons.check_circle, size: 18, color: Xp.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _placeholder = ColoredBox(
    color: Xp.well,
    child: Icon(Icons.image_outlined, color: Xp.textFaint, size: 18),
  );

  Widget _cover(String? ref) {
    if (ref == null || ref.isEmpty) return _placeholder;
    final uri = Uri.tryParse(ref);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Image.network(
        ref,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder,
      );
    }
    return Image.file(
      File(ref),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder,
    );
  }
}

/// Centered dim message for the candidates area's empty / prompt / error states.
class _CandidatesMessage extends StatelessWidget {
  const _CandidatesMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Xp.spaceXl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Xp.textDim),
      ),
    ),
  );
}
