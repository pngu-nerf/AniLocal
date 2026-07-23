import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/missing_episodes.dart';
import '../domain/models/episode.dart';
import '../domain/models/episode_list_row.dart';
import '../domain/models/episode_slot.dart';
import '../domain/models/episode_source.dart';
import '../domain/models/series.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'fix_match_screen.dart';
import 'settings_dialog.dart';
import 'library/library_search_bar.dart';
import 'theater/theater_screen.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'unmatched_screen.dart';
import 'widgets/episode_row.dart';
import 'widgets/episode_tile.dart';
import 'widgets/header_actions.dart';
import 'widgets/show_cover.dart';
import 'widgets/xp_dialog.dart';
import 'widgets/xp_screen.dart';
import 'widgets/multi_select_list.dart';

/// Whether an episode matches the live episode-search [query]. Matches on:
///  - the episode [number] by PREFIX, so it narrows as you type ("4" → 4, 40–49,
///    400–499…; "14" → 14, 140–149) — NOT arbitrary substring (so "7" never
///    matches 47, and "41" never matches 141), and
///  - the [fileName] (a present episode's filename basename) by case-insensitive
///    SUBSTRING, so text from the filename — resolution, group, etc. — is
///    searchable (a missing/ghost episode has no file, so it matches by number
///    only).
///
/// A blank query matches everything (clearing restores the full list). The
/// synthetic per-episode title is deliberately NOT matched: it is always the
/// literal `"Episode N"` (real titles aren't cached), so matching it added only
/// noise (e.g. "episode" matching everything). Pure (UI-layer, filters an
/// already-loaded list) so it's unit-testable — the episode-list analogue of
/// the homepage's `seriesMatchesQuery`.
@visibleForTesting
bool episodeMatchesQuery({
  required int number,
  String? fileName,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if ('$number'.startsWith(q)) return true;
  return fileName != null && fileName.toLowerCase().contains(q);
}

/// Series detail: cover + metadata + the episodes for this series, in the
/// homepage's blackout-XP look (its title bar, tokens, and components). With the
/// missing-episodes feature on, absent episodes appear as ghost tiles (single)
/// or bundles (consecutive runs), and hidden episodes move to a "Hidden" tab.
/// Each present episode can be played, reassigned, source-switched, or used as a
/// season-split point.
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
    required this.settings,
    required this.onRefreshMetadata,
    // Shared header actions, so the detail header matches the home header.
    required this.onFolders,
    required this.onScan,
    required this.onUnmatched,
    required this.unmatchedCount,
  });

  final Series series;
  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (read + hide/unhide). Sacred across rescans (seam #5).
  final MissingEpisodesRepository missing;

  /// ALL app-wide settings behind ONE injected object — read here (missing-
  /// enabled), forwarded to the theater (rail fraction + player prefs) and the
  /// shared settings dialog (opened identically from home + here).
  final SettingsRepository settings;

  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

  /// Shared header actions (Sources / Sync / Unmatched), forwarded so the detail
  /// header is identical to the home header. [unmatchedCount] is a snapshot.
  final Future<void> Function() onFolders;
  final Future<void> Function() onScan;
  final VoidCallback onUnmatched;
  final int unmatchedCount;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<Episode> _episodes = const [];
  Set<int> _hidden = {};
  bool _missingEnabled = true;
  bool _loading = true;

  /// True when the initial load failed (episodes couldn't be read) — shows the
  /// error state with a retry instead of hanging on the spinner.
  bool _error = false;

  /// True when NONE of the show's source files are currently reachable (e.g. the
  /// drive/mount holding them was unplugged while viewing) — shows a reconnect
  /// banner and gates playback; cached metadata + the list stay visible.
  bool _sourcesUnavailable = false;

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

  final ScrollController _scroll = ScrollController();

  /// Live episode-list search (in-memory, no reload) — mirrors the homepage
  /// library search. Filters whichever list is in front (Episodes or Hidden);
  /// empty query restores the full list.
  final TextEditingController _searchController = TextEditingController();
  String _episodeQuery = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final enabled = await widget.settings.loadMissingEnabled();
      final eps = await widget.repository.episodesFor(widget.series.anilistId);
      // The feature never applies to a not-yet-identified placeholder (no
      // AniList count, synthetic negative id) — treat it as nothing hidden.
      final hidden = (!enabled || widget.series.pending)
          ? <int>{}
          : await widget.missing.hiddenEpisodes(widget.series.anilistId);
      // The show's files are "unavailable" when NO source of any present
      // episode exists on disk (the drive/mount is gone). `any` short-circuits
      // on the first reachable file, so the connected case is cheap.
      final unavailable =
          eps.isNotEmpty &&
          !eps.any((e) => e.sources.any((s) => File(s.fileRef).existsSync()));
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _hidden = hidden;
        _missingEnabled = enabled;
        _sourcesUnavailable = unavailable;
        _loading = false;
        _error = false;
        _expandedBundles.clear();
        _bundleSelection.clear();
        _hiddenSelection = {};
        if (hidden.isEmpty) _viewingHidden = false;
      });
      widget.watchOrder.upNextBySeries().then((m) {
        if (mounted) setState(() => _next = m[widget.series.anilistId]);
      });
    } catch (_) {
      // Don't hang on the spinner — surface an error state with retry.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Update the live search query. Also drops transient selection/expansion
  /// state so a checked bundle/hidden selection can't outlive the filtered list
  /// it referred to.
  void _setQuery(String value) => setState(() {
    _episodeQuery = value;
    _hiddenSelection = {};
    _bundleSelection.clear();
    _expandedBundles.clear();
  });

  Future<void> _hide(List<int> numbers) async {
    await widget.missing.hideEpisodes(widget.series.anilistId, numbers);
    await _reload();
  }

  Future<void> _unhide(List<int> numbers) async {
    await widget.missing.unhideEpisodes(widget.series.anilistId, numbers);
    await _reload();
  }

  void _openSettings() => showAppSettingsDialog(
    context,
    settings: widget.settings,
    actions: SettingsDialogActions(
      onRefreshMetadata: widget.onRefreshMetadata,
      onRefreshed: _reload,
      loadUnmatchedCount: () async =>
          (await widget.repository.unmatchedFiles()).length,
      onOpenUnmatched: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UnmatchedScreen(
            repository: widget.repository,
            fixMatch: widget.fixMatch,
          ),
        ),
      ),
      // Edit Sources opens the same folders page the header does.
      onOpenSources: widget.onFolders,
    ),
  );

  /// Header "Sync" on the detail screen: run the home-provided sync, then reload
  /// this screen's data. No local spinner — the sync runs quietly.
  Future<void> _sync() async {
    await widget.onScan();
    if (mounted) await _reload();
  }

  String get _query =>
      widget.series.titles.romaji ??
      widget.series.titles.english ??
      widget.series.titles.native ??
      '';

  void _showReconnectHint() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            "This show's drive isn't connected. Reconnect it, then try again.",
          ),
        ),
      );
  }

  Future<void> _play(Episode e) async {
    // Files-dependent action reflects the disconnected state: don't open the
    // player onto a missing file — hint to reconnect instead.
    if (_sourcesUnavailable) {
      _showReconnectHint();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TheaterScreen(
          series: widget.series,
          initialEpisode: e,
          repository: widget.repository,
          watchState: widget.watchState,
          watchOrder: widget.watchOrder,
          settings: widget.settings,
          // Same header actions as this screen — so the theater header matches.
          unmatchedCount: widget.unmatchedCount,
          onFolders: widget.onFolders,
          onScan: _sync,
          onUnmatched: widget.onUnmatched,
          onSettings: _openSettings,
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
        return XpDialog(
          title: 'Episode ${e.number} — source',
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
            XpButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
          ],
        );
      },
    );
    if (changed == true) _reload();
  }

  Future<void> _splitFromHere(Episode from) async {
    // Split from THIS episode onward — resolved by the episode's real position
    // in the full (unfiltered) list, not a filtered row index, so a search that
    // reorders/omits rows can't split the wrong range.
    final start = _episodes.indexOf(from);
    final range = _episodes
        .sublist(start < 0 ? 0 : start)
        .map((e) => e.fileRef)
        .toList();
    // Real prior-season count: this series' AniList episode count (fallback to
    // the split point minus one). Never hardcoded.
    final prior = widget.series.episodeCount ?? (from.number - 1);
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

  // --- Tiles ----------------------------------------------------------------

  /// A present (in-library) episode tile, rendered from the [e] carried by its
  /// row — NOT a positional index into `_episodes` (which is wrong once a search
  /// filters the list). Tap plays [e]; split resolves [e]'s real position.
  Widget _episodeTile(Episode e) {
    final multi = e.hasMultipleSources;
    // A pending placeholder can't be source-pinned (no real identity to key the
    // pin to) — it always plays the automatic source. Show the source count,
    // but not the picker.
    final pinnable = multi && !widget.series.pending;
    final subtitle = [
      _name(e.fileRef),
      if (multi) '${e.sources.length} sources · from ${e.fileRef}',
      if (!e.watched && e.resumePosition > Duration.zero)
        '▸ resume ${_fmt(e.resumePosition)}',
    ].join('\n');

    // The SHARED episode tile (same as the theater rail); this list keeps the
    // now-playing affordance OFF and passes a filename/resume subtitle as the
    // detail slot, with the watched mark, source picker, and per-episode menu
    // in trailing. Tap opens the player.
    return EpisodeTile(
      number: e.number,
      title: e.title ?? 'Episode ${e.number}',
      onTap: () => _play(e),
      detail: Text(
        subtitle,
        style: const TextStyle(color: Xp.textDim, fontSize: 11),
      ),
      trailing: [
        const SizedBox(width: 8),
        if (e.watched)
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 2),
            child: Icon(Icons.check_circle, size: 18, color: Xp.accent),
          ),
        if (pinnable)
          IconButton(
            tooltip: '${e.sources.length} sources — choose…',
            icon: Badge(
              label: Text('${e.sources.length}'),
              child: const Icon(
                Icons.layers_outlined,
                color: Xp.text,
                size: 20,
              ),
            ),
            onPressed: () => _chooseSource(e),
          ),
        _episodeMenu(e, pinnable: pinnable),
      ],
    );
  }

  /// The per-episode three-dots menu for a REAL (owned) episode: the sticky
  /// Mark-as-Watched toggle, then a "Reassign Show" submenu holding the two
  /// pre-existing reassign actions, then the source picker for multi-source
  /// episodes. NO hide option — hiding is a MISSING-episode-only concept (it
  /// suppresses a ghost/gap tile); you can't hide an episode you actually have.
  Widget _episodeMenu(Episode e, {required bool pinnable}) {
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_vert, color: Xp.text),
        tooltip: 'Episode options',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            e.watched ? Icons.remove_done : Icons.done_all,
            size: 18,
          ),
          onPressed: () => _toggleWatched(e),
          child: Text(e.watched ? 'Mark as Unwatched' : 'Mark as Watched'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.swap_horiz, size: 18),
          menuChildren: [
            MenuItemButton(
              onPressed: () => _reassignOne(e),
              child: const Text('Reassign Episode'),
            ),
            MenuItemButton(
              onPressed: () => _splitFromHere(e),
              child: const Text('Reassign This and All Following Episodes'),
            ),
          ],
          child: const Text('Reassign Show'),
        ),
        if (pinnable)
          MenuItemButton(
            leadingIcon: const Icon(Icons.layers_outlined, size: 18),
            onPressed: () => _chooseSource(e),
            child: const Text('Choose source…'),
          ),
      ],
    );
  }

  /// Sticky manual watched-override toggle. Flips the episode's watched flag via
  /// the durable per-episode override (wins over the threshold, survives re-entry
  /// + refresh); progress/resume is untouched.
  Future<void> _toggleWatched(Episode e) async {
    await widget.watchState.setWatchedManual(e, watched: !e.watched);
    await _reload();
  }

  /// A faded, outlined circular badge for a missing episode's number — the
  /// shared badge in its ghost variant (so present + missing badges can't drift).
  Widget _ghostBadge(int number) =>
      EpisodeNumberBadge(number: number, ghost: true);

  /// A single missing episode (a ghost). Three-dots → "Hide missing episode".
  Widget _missingSingleTile(int number) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _ghostBadge(number),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChromeLabel(
                  'Missing',
                  upper: false,
                  color: Xp.textFaint,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ],
            ),
          ),
          ChromeLabel(
            'Episode $number',
            upper: false,
            color: Xp.textFaint,
            fontSize: 13,
            letterSpacing: 1,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Xp.textDim),
            onSelected: (v) {
              if (v == 'hide') _hide([number]);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'hide', child: Text('Hide missing episode')),
            ],
          ),
        ],
      ),
    );
  }

  /// A consecutive run of 2+ missing episodes: first on top, last on the bottom,
  /// joined by a line ("these two and everything between"). Three-dots →
  /// "Hide all" or "Select episodes to hide…" (expands inline).
  Widget _missingBundleTile(MissingBundleRow b) {
    final expanded = _expandedBundles.contains(b.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // The "first —line— last" connector, the height of two entries.
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _ghostBadge(b.first),
                      Expanded(
                        child: Center(
                          child: Container(width: 2, color: Xp.divider),
                        ),
                      ),
                      _ghostBadge(b.last),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ChromeLabel(
                          'Episode ${b.first}',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                        ChromeLabel(
                          '${b.numbers.length} missing episodes',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                        ChromeLabel(
                          'Episode ${b.last}',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Xp.textDim),
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
      padding: const EdgeInsets.fromLTRB(56, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MultiSelectList(
            key: ValueKey('bundle-${b.numbers.join('-')}'),
            itemCount: b.numbers.length,
            labelBuilder: (_, i) => Text(
              'Episode ${b.numbers[i]}',
              style: const TextStyle(color: Xp.text),
            ),
            onSelectionChanged: (sel) => setState(() {
              _bundleSelection[b.first] = {for (final i in sel) b.numbers[i]};
            }),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              XpButton(
                dense: true,
                label: 'Cancel',
                onPressed: () => setState(() {
                  _expandedBundles.remove(b.first);
                  _bundleSelection.remove(b.first);
                }),
              ),
              const SizedBox(width: 8),
              XpButton(
                dense: true,
                icon: Icons.visibility_off,
                label: 'Hide selected',
                onPressed: selected.isEmpty
                    ? null
                    : () => _hide(selected.toList()..sort()),
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
  Widget _hiddenView(List<int> hiddenSorted, String query) {
    // A search that matches no hidden episode reads as a clean empty state, not
    // a blank list.
    if (hiddenSorted.isEmpty) {
      return _emptyState(
        query.trim().isEmpty ? 'No hidden episodes' : 'No episodes match',
      );
    }
    return XpPanel(
      inset: true,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MultiSelectList(
            key: ValueKey('hidden-${hiddenSorted.join('-')}'),
            itemCount: hiddenSorted.length,
            labelBuilder: (_, i) => Text(
              'Episode ${hiddenSorted[i]}',
              style: const TextStyle(color: Xp.text),
            ),
            onSelectionChanged: (sel) => setState(() {
              _hiddenSelection = {for (final i in sel) hiddenSorted[i]};
            }),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: XpButton(
              icon: Icons.visibility,
              label: 'Unhide',
              onPressed: _hiddenSelection.isEmpty
                  ? null
                  : () => _unhide(_hiddenSelection.toList()..sort()),
            ),
          ),
        ],
      ),
    );
  }

  /// The downloaded-episode indicator ("⬇ N of M +X"), consistent with the
  /// library card and reflecting hidden exclusions.
  Widget _downloadIndicator(DownloadTally tally) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.download, size: 15, color: Xp.textDim),
          const SizedBox(width: 4),
          Text(
            tally.total != null
                ? '${tally.inRange} of ${tally.total}'
                : '${tally.inRange}',
            style: const TextStyle(color: Xp.textDim, fontSize: 12),
          ),
          if (tally.outOfRange > 0)
            Text(
              '  +${tally.outOfRange}',
              style: const TextStyle(color: Xp.warning, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color iconColor,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: XpPanel(
        color: Xp.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Xp.text, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            XpButton(
              dense: true,
              icon: Icons.refresh,
              label: actionLabel,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final title = series.displayTitle;

    // The ONE shared screen shell (XpScreen): a VFD back tab + the SAME
    // HeaderActionsBar as home/theater, readout reading "AniLocal <TITLE>".
    // Theme is applied app-wide, so no per-screen wrap.
    return XpScreen(
      title: title,
      trailing: HeaderActionsBar(
        // No local spinner on the detail screen — sync runs quietly.
        scanning: false,
        unmatchedCount: widget.unmatchedCount,
        onFolders: widget.onFolders,
        onScan: _sync,
        onUnmatched: widget.onUnmatched,
        onSettings: _openSettings,
      ),
      child: _content(series, title),
    );
  }

  Widget _content(Series series, String title) {
    final art = series.coverImageRef;
    final showMissing = _missingEnabled && !series.pending;
    final effectiveHidden = showMissing ? _hidden : const <int>{};
    final slots = computeEpisodeSlots(
      present: _episodes,
      hidden: effectiveHidden,
      episodeCount: series.episodeCount,
    );
    final tally = computeDownloadTally(slots, series.episodeCount);
    final hiddenSorted = _hidden.toList()..sort();
    final hiddenTabAvailable = showMissing && hiddenSorted.isNotEmpty;

    // Live search filters the list in front of the user. On the Episodes tab it
    // filters present + ghost slots (dropping hidden, which never show there)
    // and re-groups the survivors — so a filtered run of missing episodes still
    // bundles/singles per the existing 2+-consecutive rule (grouping is computed
    // live). Empty query → full list, normal grouping.
    final q = _episodeQuery.trim().toLowerCase();
    final List<EpisodeListRow> rows;
    if (!showMissing) {
      rows = [
        for (final e in _episodes)
          if (episodeMatchesQuery(
            number: e.number,
            fileName: _name(e.fileRef),
            query: q,
          ))
            PresentRow(e),
      ];
    } else if (q.isEmpty) {
      rows = groupIntoRows(slots);
    } else {
      rows = groupIntoRows([
        for (final s in slots)
          if (s.status != EpisodeStatus.hidden &&
              episodeMatchesQuery(
                number: s.episode?.number ?? s.number,
                // A ghost (missing) slot has no file → number-only match.
                fileName: s.episode == null ? null : _name(s.episode!.fileRef),
                query: q,
              ))
            s,
      ]);
    }
    final visibleHidden = q.isEmpty
        ? hiddenSorted
        : [
            for (final n in hiddenSorted)
              if (episodeMatchesQuery(number: n, query: q)) n,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Disconnected-drive banner (cached info stays visible below it).
        if (_sourcesUnavailable && !_loading && !_error)
          _banner(
            icon: Icons.link_off,
            iconColor: Xp.warning,
            message:
                "This show's drive isn't connected — reconnect it to play or "
                'change files.',
            actionLabel: 'Try again',
            onAction: _reload,
          ),
        Expanded(
          child: XpScrollbar(
            controller: _scroll,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                // Header: cover + titles + metadata + downloaded indicator.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover through the show's picture mode (blur/removed apply
                    // here too, consistently with the grid + player).
                    XpBevel(
                      raised: false,
                      color: Xp.well,
                      child: SizedBox(
                        width: 150,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ShowCover(
                            imagePath: art,
                            pictureMode: series.pictureMode,
                            placeholderIcon: series.pending
                                ? Icons.hourglass_empty
                                : Icons.movie_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (series.titles.romaji != null)
                            Text(
                              series.titles.romaji!,
                              style: const TextStyle(color: Xp.text),
                            ),
                          if (series.titles.native != null)
                            Text(
                              series.titles.native!,
                              style: const TextStyle(color: Xp.textDim),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            series.pending
                                ? 'Identifying… (not yet matched to AniList)'
                                : [
                                    if (series.format != null) series.format,
                                    if (series.episodeCount != null)
                                      '${series.episodeCount} episodes',
                                    'AniList #${series.anilistId}',
                                  ].join(' · '),
                            style: const TextStyle(
                              color: Xp.textDim,
                              fontSize: 12,
                            ),
                          ),
                          if (!series.pending && !_loading && !_error)
                            _downloadIndicator(tally),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_next != null && !_loading && !_error)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: XpButton(
                      icon: Icons.play_arrow,
                      label: _next!.seriesAnilistId == series.anilistId
                          ? 'Play next: Episode ${_next!.number}'
                          : 'Play next: Episode ${_next!.number} (sequel)',
                      onPressed: () => _play(_next!),
                    ),
                  ),
                const SizedBox(height: 12),
                // Episodes header + Episodes/Hidden tab toggle.
                Row(
                  children: [
                    const Text(
                      'Episodes',
                      style: TextStyle(
                        color: Xp.text,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (hiddenTabAvailable) ...[
                      XpButton(
                        dense: true,
                        label: 'Episodes',
                        selected: !_viewingHidden,
                        onPressed: () => setState(() => _viewingHidden = false),
                      ),
                      const SizedBox(width: 4),
                      XpButton(
                        dense: true,
                        label: 'Hidden (${hiddenSorted.length})',
                        selected: _viewingHidden,
                        onPressed: () => setState(() => _viewingHidden = true),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Live episode search, pinned below the tab control, above the
                // list — the same component + behavior as the homepage search.
                if (!_loading && !_error) ...[
                  LibrarySearchBar(
                    controller: _searchController,
                    hintText: 'Search episodes',
                    onChanged: _setQuery,
                    onClear: () {
                      _searchController.clear();
                      _setQuery('');
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error)
                  _errorState()
                else if (_viewingHidden && hiddenTabAvailable)
                  _hiddenView(visibleHidden, q)
                else
                  _episodeWell(rows, q),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The error state: a load failure shows this instead of an endless spinner.
  Widget _errorState() {
    return XpPanel(
      inset: true,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Xp.warning, size: 32),
          const SizedBox(height: 8),
          const Text(
            "Couldn't load this show's episodes.",
            style: TextStyle(color: Xp.text),
          ),
          const SizedBox(height: 12),
          XpButton(icon: Icons.refresh, label: 'Try again', onPressed: _reload),
        ],
      ),
    );
  }

  /// The episode list in a sunken XP well, rows separated by hairlines. Dimmed
  /// when the drive is disconnected (files-dependent affordances read inert).
  Widget _episodeWell(List<EpisodeListRow> rows, String query) {
    final tiles = _episodeRows(rows);
    final Widget well;
    if (tiles.isEmpty) {
      // Distinguish "nothing here" from "search matched nothing".
      well = _emptyState(
        query.trim().isEmpty ? 'No episodes' : 'No episodes match',
      );
    } else {
      final children = <Widget>[];
      for (var i = 0; i < tiles.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 1, color: Xp.divider));
        }
        children.add(tiles[i]);
      }
      well = XpPanel(
        inset: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    // Cached list stays visible when disconnected, just dimmed to read inert.
    return Opacity(opacity: _sourcesUnavailable ? 0.5 : 1, child: well);
  }

  /// A clean centered message in a sunken well — used for empty / no-match
  /// episode lists.
  Widget _emptyState(String message) => XpPanel(
    inset: true,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(message, style: const TextStyle(color: Xp.textDim)),
      ),
    ),
  );

  /// Materialize the grouped rows into tile widgets. Present tiles render from
  /// the Episode the row carries (never a positional index), so a filtered list
  /// shows — and acts on — the correct episodes.
  List<Widget> _episodeRows(List<EpisodeListRow> rows) {
    final widgets = <Widget>[];
    for (final row in rows) {
      switch (row) {
        case PresentRow(:final episode):
          widgets.add(_episodeTile(episode));
        case MissingSingleRow(:final number):
          widgets.add(_missingSingleTile(number));
        case MissingBundleRow():
          widgets.add(_missingBundleTile(row));
      }
    }
    return widgets;
  }
}
