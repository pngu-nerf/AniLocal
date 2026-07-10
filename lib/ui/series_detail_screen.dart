import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/missing_episodes.dart';
import '../domain/models/episode.dart';
import '../domain/models/episode_list_row.dart';
import '../domain/models/episode_source.dart';
import '../domain/models/series.dart';
import '../domain/models/skip_mode.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'fix_match_screen.dart';
import 'theater/theater_screen.dart';
import 'widgets/multi_select_list.dart';
import 'window_chrome.dart';

/// Series detail: cover + metadata + the episodes for this series. With the
/// missing-episodes feature on, absent episodes appear as ghost tiles (single)
/// or bundles (consecutive runs), and hidden episodes move to a "Hidden" tab.
/// Each present episode can be reassigned or used as a season-split point.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.missing,
    required this.loadMissingEnabled,
    required this.loadAutoPlayNext,
    required this.loadSkipMode,
    required this.loadRailFraction,
    required this.setRailFraction,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (read + hide/unhide). Sacred across rescans (seam #5).
  final MissingEpisodesRepository missing;

  /// Whether the missing-episodes feature is enabled (global setting). When
  /// false: no ghost tiles, no Hidden tab, counts ignore hidden state.
  final Future<bool> Function() loadMissingEnabled;

  final Future<bool> Function() loadAutoPlayNext;
  final Future<SkipMode> Function() loadSkipMode;
  final Future<double> Function() loadRailFraction;
  final Future<void> Function(double fraction) setRailFraction;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<Episode> _episodes = const [];
  Set<int> _hidden = {};
  bool _missingEnabled = true;
  bool _loading = true;

  /// Which tab of the episode area is showing (false = Episodes, true = Hidden).
  bool _viewingHidden = false;

  Episode? _next; // next episode to watch for this series (relations-aware)

  /// Bundles currently expanded inline into a per-episode hide checklist, keyed
  /// by the bundle's first episode number.
  final Set<int> _expandedBundles = {};

  /// The checked episode numbers per expanded bundle, and per the Hidden tab —
  /// held here so the action buttons (Hide / Unhide) read the live selection.
  final Map<int, Set<int>> _bundleSelection = {};
  Set<int> _hiddenSelection = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final enabled = await widget.loadMissingEnabled();
    final eps = await widget.repository.episodesFor(widget.series.anilistId);
    // The feature never applies to a not-yet-identified placeholder (no AniList
    // count, synthetic negative id) — treat it as having nothing hidden.
    final hidden = (!enabled || widget.series.pending)
        ? <int>{}
        : await widget.missing.hiddenEpisodes(widget.series.anilistId);
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _hidden = hidden;
      _missingEnabled = enabled;
      _loading = false;
      _expandedBundles.clear();
      _bundleSelection.clear();
      _hiddenSelection = {};
      if (hidden.isEmpty) _viewingHidden = false;
    });
    widget.watchOrder.upNextBySeries().then((m) {
      if (mounted) setState(() => _next = m[widget.series.anilistId]);
    });
  }

  Future<void> _hide(List<int> numbers) async {
    await widget.missing.hideEpisodes(widget.series.anilistId, numbers);
    await _reload();
  }

  Future<void> _unhide(List<int> numbers) async {
    await widget.missing.unhideEpisodes(widget.series.anilistId, numbers);
    await _reload();
  }

  String get _query =>
      widget.series.titles.romaji ??
      widget.series.titles.english ??
      widget.series.titles.native ??
      '';

  Future<void> _play(Episode e) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TheaterScreen(
          series: widget.series,
          initialEpisode: e,
          repository: widget.repository,
          watchState: widget.watchState,
          watchOrder: widget.watchOrder,
          loadAutoPlayNext: widget.loadAutoPlayNext,
          loadSkipMode: widget.loadSkipMode,
          loadRailFraction: widget.loadRailFraction,
          setRailFraction: widget.setRailFraction,
        ),
      ),
    );
    _reload(); // reflect updated watched / resume position / up-next
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _reassignOne(Episode e) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: [e.fileRef],
          prefillQuery: _query,
        ),
      ),
    );
    if (done == true) _reload();
  }

  static String _name(String path) => path.split(Platform.pathSeparator).last;

  /// Pick which source a multi-source episode plays from: "Automatic" (folder
  /// priority — the default) or a specific copy (a manual pin that survives
  /// rescans). Switching only changes which file opens — nothing on disk moves.
  Future<void> _chooseSource(Episode e) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final priorityDefault = e.sources.first; // sources are priority-ordered
        return AlertDialog(
          title: Text('Episode ${e.number} — source'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    e.pinnedSourceFolder == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: const Text('Automatic (highest priority)'),
                  subtitle: Text('Plays from ${priorityDefault.fileRef}'),
                  onTap: () async {
                    await widget.sourceSelection.clearSource(e);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
                const Divider(height: 1),
                for (final EpisodeSource s in e.sources)
                  ListTile(
                    leading: Icon(
                      e.pinnedSourceFolder == s.folderPath
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(s.fileRef),
                    subtitle: s == priorityDefault
                        ? const Text('default')
                        : null,
                    onTap: () async {
                      await widget.sourceSelection.selectSource(
                        e,
                        folderPath: s.folderPath,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    if (changed == true) _reload();
  }

  Future<void> _splitFromHere(List<Episode> all, int index) async {
    final range = all.sublist(index).map((e) => e.fileRef).toList();
    // Real prior-season count: this series' AniList episode count (fallback to
    // the split point minus one). Never hardcoded.
    final prior = widget.series.episodeCount ?? (all[index].number - 1);
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: range,
          prefillQuery: _query,
          isSplit: true,
          priorEpisodeCount: prior,
        ),
      ),
    );
    if (done == true) _reload();
  }

  /// A present (in-library) episode. [index] is its position in [episodes] (the
  /// present-only list), needed for the season-split action.
  Widget _episodeTile(List<Episode> episodes, int index) {
    final e = episodes[index];
    final multi = e.hasMultipleSources;
    // A pending placeholder can't be source-pinned (it has no real identity to
    // key the pin to) — it always plays the automatic source. Show the source
    // count, but not the picker.
    final pinnable = multi && !widget.series.pending;
    return ListTile(
      dense: true,
      onTap: () => _play(e),
      leading: CircleAvatar(child: Text('${e.number}')),
      title: Text(e.title ?? 'Episode ${e.number}'),
      subtitle: Text(
        [
          _name(e.fileRef),
          if (multi) '${e.sources.length} sources · from ${e.fileRef}',
          if (!e.watched && e.resumePosition > Duration.zero)
            '▸ resume ${_fmt(e.resumePosition)}',
        ].join('\n'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (e.watched)
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (pinnable)
            IconButton(
              tooltip: '${e.sources.length} sources — choose…',
              icon: Badge(
                label: Text('${e.sources.length}'),
                child: const Icon(Icons.layers_outlined),
              ),
              onPressed: () => _chooseSource(e),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reassign') _reassignOne(e);
              if (v == 'split') _splitFromHere(episodes, index);
              if (v == 'source') _chooseSource(e);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reassign',
                child: Text('Reassign this episode…'),
              ),
              const PopupMenuItem(
                value: 'split',
                child: Text('Split: reassign from here…'),
              ),
              if (pinnable)
                const PopupMenuItem(
                  value: 'source',
                  child: Text('Choose source…'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A faded circular badge for a missing episode's number.
  Widget _ghostBadge(int number) {
    final dim = Theme.of(context).disabledColor;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: dim, width: 1.5),
      ),
      child: Text('$number', style: TextStyle(color: dim, fontSize: 12)),
    );
  }

  /// A single missing episode (a ghost). Three-dots → "Hide missing episode".
  Widget _missingSingleTile(int number) {
    final dim = Theme.of(context).disabledColor;
    return ListTile(
      dense: true,
      leading: _ghostBadge(number),
      title: Text('Episode $number', style: TextStyle(color: dim)),
      subtitle: Text('Missing', style: TextStyle(color: dim)),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'hide') _hide([number]);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'hide', child: Text('Hide missing episode')),
        ],
      ),
    );
  }

  /// A consecutive run of 2+ missing episodes: first on top, last on the bottom,
  /// joined by a line ("these two and everything between"). Three-dots →
  /// "Hide all" or "Select episodes to hide…" (expands inline).
  Widget _missingBundleTile(MissingBundleRow b) {
    final theme = Theme.of(context);
    final dim = theme.disabledColor;
    final expanded = _expandedBundles.contains(b.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 100,
          child: Row(
            children: [
              // The "first —line— last" connector, the height of two entries.
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _ghostBadge(b.first),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: dim.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    _ghostBadge(b.last),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Episode ${b.first}',
                        style: TextStyle(
                          color: dim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${b.numbers.length} missing episodes',
                        style: theme.textTheme.bodySmall?.copyWith(color: dim),
                      ),
                      Text(
                        'Episode ${b.last}',
                        style: TextStyle(
                          color: dim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'hideAll') _hide(b.numbers);
                  if (v == 'select') {
                    setState(() => _expandedBundles.add(b.first));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'hideAll', child: Text('Hide all')),
                  PopupMenuItem(
                    value: 'select',
                    child: Text('Select episodes to hide…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (expanded) _bundleExpansion(b),
      ],
    );
  }

  /// The inline per-episode checklist a bundle expands into: the reusable
  /// multi-select over the run's episodes + a Hide button for the checked ones.
  Widget _bundleExpansion(MissingBundleRow b) {
    final selected = _bundleSelection[b.first] ?? const <int>{};
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MultiSelectList(
            key: ValueKey('bundle-${b.numbers.join('-')}'),
            itemCount: b.numbers.length,
            labelBuilder: (_, i) => Text('Episode ${b.numbers[i]}'),
            onSelectionChanged: (sel) => setState(() {
              _bundleSelection[b.first] = {for (final i in sel) b.numbers[i]};
            }),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _expandedBundles.remove(b.first);
                  _bundleSelection.remove(b.first);
                }),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => _hide(selected.toList()..sort()),
                child: const Text('Hide selected'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The Hidden tab: every hidden episode individually, with the reusable
  /// multi-select + an Unhide button. No confirm dialog — select-then-unhide is
  /// the two-step safeguard.
  Widget _hiddenView(List<int> hiddenSorted) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MultiSelectList(
            key: ValueKey('hidden-${hiddenSorted.join('-')}'),
            itemCount: hiddenSorted.length,
            labelBuilder: (_, i) => Text('Episode ${hiddenSorted[i]}'),
            onSelectionChanged: (sel) => setState(() {
              _hiddenSelection = {for (final i in sel) hiddenSorted[i]};
            }),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _hiddenSelection.isEmpty
                  ? null
                  : () => _unhide(_hiddenSelection.toList()..sort()),
              icon: const Icon(Icons.visibility),
              label: const Text('Unhide'),
            ),
          ),
        ],
      ),
    );
  }

  /// The downloaded-episode indicator ("⬇ N of M +X"), consistent with the
  /// library card and reflecting hidden exclusions.
  Widget _downloadIndicator(DownloadTally tally) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.download, size: 16, color: theme.hintColor),
          const SizedBox(width: 4),
          Text(
            tally.total != null
                ? '${tally.inRange} of ${tally.total}'
                : '${tally.inRange}',
            style: theme.textTheme.bodySmall,
          ),
          if (tally.outOfRange > 0)
            Text(
              '  +${tally.outOfRange}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final title =
        series.titles.english ??
        series.titles.romaji ??
        series.titles.native ??
        '#${series.anilistId}';
    final art = series.coverImageRef;

    final showMissing = _missingEnabled && !series.pending;
    final effectiveHidden = showMissing ? _hidden : const <int>{};
    final slots = computeEpisodeSlots(
      present: _episodes,
      hidden: effectiveHidden,
      episodeCount: series.episodeCount,
    );
    final tally = computeDownloadTally(slots, series.episodeCount);
    final rows = showMissing
        ? groupIntoRows(slots)
        : [for (final e in _episodes) PresentRow(e)];
    final hiddenSorted = _hidden.toList()..sort();
    final hiddenTabAvailable = showMissing && hiddenSorted.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // Inset the back button clear of the traffic lights (hidden title bar).
        leadingWidth: kAppBarLeadingWidth,
        leading: trafficLightBackButton(),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (art != null && File(art).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(art), width: 150, fit: BoxFit.cover),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (series.titles.romaji != null)
                      Text(series.titles.romaji!),
                    if (series.titles.native != null)
                      Text(series.titles.native!),
                    const SizedBox(height: 8),
                    Text(
                      series.pending
                          // Placeholder: not yet identified, so no AniList
                          // id/format to show — say so plainly.
                          ? 'Identifying… (not yet matched to AniList)'
                          : [
                              if (series.format != null) series.format,
                              if (series.episodeCount != null)
                                '${series.episodeCount} episodes',
                              'AniList #${series.anilistId}',
                            ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!series.pending) _downloadIndicator(tally),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_next != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _play(_next!),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _next!.seriesAnilistId == series.anilistId
                      ? 'Play next: Episode ${_next!.number}'
                      : 'Play next: Episode ${_next!.number} (sequel)',
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Episodes', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (hiddenTabAvailable)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: false, label: Text('Episodes')),
                    ButtonSegment(
                      value: true,
                      label: Text('Hidden (${hiddenSorted.length})'),
                    ),
                  ],
                  selected: {_viewingHidden},
                  onSelectionChanged: (s) =>
                      setState(() => _viewingHidden = s.first),
                ),
            ],
          ),
          const Divider(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_viewingHidden && hiddenTabAvailable)
            _hiddenView(hiddenSorted)
          else
            ..._episodeRows(rows),
        ],
      ),
    );
  }

  /// Materialize the grouped rows into tile widgets, tracking each present
  /// episode's index in the present-only list (for the season-split action).
  List<Widget> _episodeRows(List<EpisodeListRow> rows) {
    final widgets = <Widget>[];
    var presentIndex = 0;
    for (final row in rows) {
      switch (row) {
        case PresentRow():
          widgets.add(_episodeTile(_episodes, presentIndex));
          presentIndex++;
        case MissingSingleRow(:final number):
          widgets.add(_missingSingleTile(number));
        case MissingBundleRow():
          widgets.add(_missingBundleTile(row));
      }
    }
    return widgets;
  }
}
