import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../diagnostics/app_log.dart';
import '../domain/folder_health.dart';
import '../domain/format_duration.dart';
import '../domain/missing_episodes.dart';
import '../domain/models/episode.dart';
import '../domain/models/episode_list_row.dart';
import '../domain/models/episode_slot.dart';
import '../domain/models/episode_source.dart';
import '../domain/models/series.dart';
import '../domain/watch_order.dart';
import 'library/library_search_bar.dart';
import 'library_services.dart';
import 'metadata_failure_message.dart';
import 'routes.dart';
import 'series_detail/missing_episode_tiles.dart';
import 'settings/settings_window.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/download_tally_label.dart';
import 'widgets/episode_tile.dart';
import 'widgets/guarded.dart';
import 'widgets/show_cover.dart';
import 'widgets/xp_banner.dart';
import 'widgets/xp_dialog.dart';

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

/// The rows the show page lists for [episodes], given the hidden set, the
/// show's episode count, whether the missing-episodes feature is on, and the
/// live search. Pure: the grouping and filtering were inlined in `build`,
/// where they re-ran on every rebuild and could not be tested.
@visibleForTesting
List<EpisodeListRow> episodeRowsFor({
  required List<Episode> episodes,
  required Set<int> hidden,
  required int? episodeCount,
  required bool showMissing,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (!showMissing) {
    return [
      for (final e in episodes)
        if (episodeMatchesQuery(
          number: e.number,
          fileName: _basename(e.fileRef),
          query: q,
        ))
          PresentRow(e),
    ];
  }
  final slots = computeEpisodeSlots(
    present: episodes,
    hidden: hidden,
    episodeCount: episodeCount,
  );
  if (q.isEmpty) return groupIntoRows(slots);
  // Filter present + ghost slots (dropping hidden, which never show here) and
  // re-group the survivors — so a filtered run of missing episodes still
  // bundles/singles per the existing 2+-consecutive rule.
  return groupIntoRows([
    for (final s in slots)
      if (s.status != EpisodeStatus.hidden &&
          episodeMatchesQuery(
            number: s.episode?.number ?? s.number,
            // A ghost (missing) slot has no file → number-only match.
            fileName: s.episode == null ? null : _basename(s.episode!.fileRef),
            query: q,
          ))
        s,
  ]);
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Series detail: cover + metadata + the episodes for this series. With the
/// missing-episodes feature on, absent episodes appear as ghost tiles (single)
/// or bundles (consecutive runs), and hidden episodes move to a "Hidden" tab.
/// Each present episode can be played, reassigned, source-switched, or used as a
/// season-split point.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.series,
    required this.services,
    required this.header,
  });

  final Series series;

  /// Every repository and the settings bundle (see [LibraryServices]).
  final LibraryServices services;

  /// Shared header actions (Scan / Unmatched), forwarded so this header is
  /// identical to the home header. The unmatched count it carries is the
  /// value at push time; this screen re-reads it on every reload (a scan from
  /// here can change it) and publishes the live number.
  final HeaderHooks header;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

/// Why a show's files cannot be reached — see `_unreachable`.
enum _Unreachable { missing, denied }

class _SeriesDetailScreenState extends State<SeriesDetailScreen>
    with HeaderPublisher {
  LibraryServices get _services => widget.services;

  /// The show as LAST READ. Seeded from the push-time value so the hero
  /// paints at once, then re-read on every reload: after a reassign, a split
  /// or a rescan the title, cover, count and picture mode follow. Null once
  /// the repository says the show is gone (pruned, or re-identified under
  /// another id) — the page then says so instead of showing the old identity.
  late Series? _series = widget.series;

  /// Why the show's files cannot be reached right now, or null when they can:
  /// `missing` (its folders' volumes are not mounted — reconnect) or `denied`
  /// (a folder's TCC category is refused — System Settings). Two different
  /// remedies, so two different banners; the old single flag sent a
  /// permission problem to the "reconnect the drive" message.
  _Unreachable? _unreachable;

  List<Episode> _episodes = const [];
  Set<int> _hidden = {};
  bool _missingEnabled = true;
  bool _loading = true;

  /// True when the initial load failed (episodes couldn't be read) — shows the
  /// error state with a retry instead of hanging on the spinner.
  bool _error = false;

  bool get _sourcesUnavailable => _unreachable != null;

  /// Which tab of the episode area is showing (false = Episodes, true = Hidden).
  bool _viewingHidden = false;

  Episode? _next; // next episode to watch for this series

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
    _services.scanning.addListener(_onScanningChanged);
    _services.scan.progress.addListener(_onScanningChanged);
    _services.unmatchedCount.addListener(_onScanningChanged);
    _services.missingFolderPaths.addListener(_onFolderHealthChanged);
    _services.accessIssues.addListener(_onFolderHealthChanged);
    unawaited(_reload());
  }

  /// A drive plugged in or a permission granted reaches this page without a
  /// reload: the banner and the gating follow the shared folder health.
  void _onFolderHealthChanged() {
    if (mounted) setState(() => _unreachable = _unreachableFor(_episodes));
  }

  @override
  void dispose() {
    _services.scanning.removeListener(_onScanningChanged);
    _services.scan.progress.removeListener(_onScanningChanged);
    _services.unmatchedCount.removeListener(_onScanningChanged);
    _services.missingFolderPaths.removeListener(_onFolderHealthChanged);
    _services.accessIssues.removeListener(_onFolderHealthChanged);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScanningChanged() {
    if (mounted) setState(() {});
  }

  /// Monotonic run counter: `_reload` is called from ten places (return from
  /// the player, a hide, a settings close, a scan…) and runs overlap; the
  /// older run finishing last must not win.
  int _reloadGeneration = 0;

  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    try {
      // Independent — the missing-episodes setting doesn't gate WHICH episodes
      // exist, only whether gaps are surfaced — so they wait together instead
      // of one after the other. `hiddenEpisodes` below is NOT parallelised with
      // them: it genuinely depends on `enabled`.
      final (enabled, eps, series) = await (
        _services.settings.loadMissingEnabled(),
        _services.repository.episodesFor(widget.series.seriesId),
        // LIVE: the show itself, not the push-time snapshot.
        _services.repository.seriesById(widget.series.seriesId),
      ).wait;
      // The feature never applies to a not-yet-identified placeholder (no
      // episode count, synthetic negative id) — treat it as nothing hidden.
      final hidden = (!enabled || (series?.pending ?? widget.series.pending))
          ? <int>{}
          : await _services.missingEpisodes.hiddenEpisodes(
              widget.series.seriesId,
            );
      // Folder health first (it names the cause); a probe of the files only
      // when the folders are healthy but the files might still be gone.
      var unreachable = _unreachableFor(eps);
      if (unreachable == null && eps.isNotEmpty && !await _anyReachable(eps)) {
        unreachable = _Unreachable.missing;
      }
      if (!mounted || generation != _reloadGeneration) return;
      setState(() {
        _series = series;
        _episodes = eps;
        _hidden = hidden;
        _missingEnabled = enabled;
        _unreachable = unreachable;
        _loading = false;
        _error = false;
        _expandedBundles.clear();
        _bundleSelection.clear();
        _hiddenSelection = {};
        if (hidden.isEmpty) _viewingHidden = false;
        // The ONE "what's next" rule, over the list already in hand — the
        // same function the repository applies library-wide for the cards.
        _next = nextToWatch(eps);
      });
    } catch (e, stack) {
      // Don't hang on the spinner — surface an error state with retry, and
      // keep the cause so the message has a diagnosis path behind it.
      AppLog.error('Show page: episode load failed', error: e, stack: stack);
      if (!mounted || generation != _reloadGeneration) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// The folder-health verdict for [eps]: every source folder unmounted →
  /// missing; any source folder in a denied category → denied; else null.
  /// The same sets the library greys cards from, so the two cannot disagree.
  _Unreachable? _unreachableFor(List<Episode> eps) {
    final folders = <String>{
      for (final e in eps)
        for (final s in e.sources) s.folderPath,
    };
    if (folders.isEmpty) return null;
    final denied = _services.accessIssues.value.toSet();
    if (folders.any((f) => denied.contains(_services.categoryLabelOf(f)))) {
      return _Unreachable.denied;
    }
    if (seriesUnavailable(folders, _services.missingFolderPaths.value)) {
      return _Unreachable.missing;
    }
    return null;
  }

  /// Whether ANY source of any present episode exists on disk. Async and
  /// short-circuiting: the old `existsSync` over every source ran on the UI
  /// isolate, and on an offline SMB/NFS mount it blocked the whole app for as
  /// long as the kernel took to give up.
  static Future<bool> _anyReachable(List<Episode> eps) async {
    for (final e in eps) {
      for (final s in e.sources) {
        if (await File(s.fileRef).exists()) return true;
      }
    }
    return false;
  }

  /// Test hook for the derived value — see test/detail_first_load_test.dart.
  @visibleForTesting
  Episode? get debugNextEpisode => _next;

  /// Update the live search query. Also drops transient selection/expansion
  /// state so a checked bundle/hidden selection can't outlive the filtered list
  /// it referred to.
  void _setQuery(String value) => setState(() {
    _episodeQuery = value;
    _hiddenSelection = {};
    _bundleSelection.clear();
    _expandedBundles.clear();
  });

  Future<void> _hide(List<int> numbers) => guarded('hide episodes', () async {
    await _services.missingEpisodes.hideEpisodes(
      widget.series.seriesId,
      numbers,
    );
    await _reload();
  }, onError: _sayWriteFailed);

  Future<void> _unhide(List<int> numbers) =>
      guarded('unhide episodes', () async {
        await _services.missingEpisodes.unhideEpisodes(
          widget.series.seriesId,
          numbers,
        );
        await _reload();
      }, onError: _sayWriteFailed);

  /// The header's ⚙ action — the one door to every setting, Folders included.
  ///
  /// AWAITED: Folders live in this window, and reordering them changes which
  /// copy of a duplicated episode plays; this screen renders those paths, so
  /// it re-reads once the window closes — after ANY visit, since the skip floor
  /// and the missing-episodes toggle are read fresh by `_reload` too.
  Future<void> _openSettings() async {
    await showAppSettingsDialog(
      context,
      settings: _services.settings,
      actions: _services.settingsActions.forScreen(
        onRefreshed: _reload,
        loadUnmatchedCount: () async => _services.unmatchedCount.value,
        onOpenUnmatched: widget.header.onUnmatched,
      ),
    );
    if (mounted) await _reload();
  }

  /// Header "Scan" on the show page: run the home-provided scan, then reload
  /// this screen's data. No local spinner beyond the shared header one.
  Future<void> _scan() async {
    await widget.header.onScan();
    if (mounted) await _reload();
  }

  HeaderHooks get _header =>
      HeaderHooks(onScan: _scan, onUnmatched: widget.header.onUnmatched);

  /// What the fix-match search box is pre-filled with: the show's best title,
  /// as last read.
  String get _fixMatchPrefill {
    final titles = (_series ?? widget.series).titles;
    return titles.romaji ?? titles.english ?? titles.native ?? '';
  }

  void _showReconnectHint() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _unreachable == _Unreachable.denied
                ? "AniLocal can't read this show's folder. Grant access in "
                      'System Settings › Privacy & Security › Files and Folders.'
                : "This show's drive isn't connected. Reconnect it, then try "
                      'again.',
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
    await AppRoutes.theater(
      context,
      services: _services,
      series: _series ?? widget.series,
      episode: e,
      header: _header,
      onSettings: _openSettings,
    );
    unawaited(_reload()); // reflect updated watched / resume position / up-next
  }

  Future<void> _reassignOne(Episode e) async {
    final done = await AppRoutes.fixMatch(
      context,
      services: _services,
      filePaths: [e.fileRef],
      prefillQuery: _fixMatchPrefill,
    );
    if (done == true) unawaited(_reload());
  }

  /// Pick which source a multi-source episode plays from: "Automatic" (folder
  /// priority — the default) or a specific copy (a manual pin that survives
  /// rescans). Switching only changes which file opens — nothing on disk moves.
  Future<void> _chooseSource(Episode e) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final priorityDefault = e.sources.first; // sources are priority-ordered
        return XpDialog(
          title: '${e.displayTitle} — source',
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
                    await _services.sourceSelection.clearSource(e);
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
                      await _services.sourceSelection.selectSource(
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
    if (changed == true) unawaited(_reload());
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
    // Real prior-season count: this show's episode count (fallback to the
    // split point minus one). Never hardcoded.
    final prior = (_series ?? widget.series).episodeCount ?? (from.number - 1);
    final done = await AppRoutes.fixMatch(
      context,
      services: _services,
      filePaths: range,
      prefillQuery: _fixMatchPrefill,
      isSplit: true,
      priorEpisodeCount: prior,
    );
    if (done == true) unawaited(_reload());
  }

  // --- Tiles ----------------------------------------------------------------

  /// A present (in-library) episode tile, rendered from the [e] carried by its
  /// row — NOT a positional index into `_episodes` (which is wrong once a search
  /// filters the list). Tap plays [e]; split resolves [e]'s real position.
  Widget _episodeTile(Episode e) {
    final multi = e.hasMultipleSources;
    // A pending placeholder can't be source-pinned (no real identity to key a
    // pin to) — it always plays the automatic source. Show the source count,
    // but not the picker.
    final pinnable = multi && !(_series ?? widget.series).pending;
    final subtitle = [
      _basename(e.fileRef),
      if (multi) '${e.sources.length} copies · playing ${e.fileRef}',
      if (!e.watched && e.resumePosition > Duration.zero)
        '▸ resume ${formatDuration(e.resumePosition)}',
    ].join('\n');

    // The SHARED episode tile (same as the theater rail); this list keeps the
    // now-playing affordance OFF and passes a filename/resume subtitle as the
    // detail slot, with the watched mark, source picker, and per-episode menu
    // in trailing. Tap opens the player.
    return EpisodeTile(
      number: e.number,
      title: e.displayTitle,
      onTap: () => _play(e),
      detail: Text(
        subtitle,
        style: const TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeCaption),
      ),
      trailing: [
        const SizedBox(width: Xp.spaceS),
        if (e.watched)
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 2),
            child: Icon(Icons.check_circle, size: 18, color: Xp.accent),
          ),
        if (pinnable)
          IconButton(
            tooltip: '${e.sources.length} copies — choose…',
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
            child: const Text('Choose copy…'),
          ),
      ],
    );
  }

  /// Sticky manual watched-override toggle. Flips the episode's watched flag via
  /// the durable per-episode override (wins over the threshold, survives re-entry
  /// + refresh); progress/resume is untouched.
  Future<void> _toggleWatched(Episode e) => guarded('mark watched', () async {
    await _services.watchState.setWatchedManual(e, watched: !e.watched);
    await _reload();
  }, onError: _sayWriteFailed);

  void _sayWriteFailed(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("That didn't save. ${userFacingMessage(e)}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    publishHeader();
    final series = _series;
    if (series == null) return _goneState();
    return _content(series);
  }

  /// The show left the library while this page was open — pruned by a
  /// rescan, or every file re-identified under another show. Information
  /// fails NEUTRAL: say so, offer the way back; never keep showing a title
  /// and a cover the library no longer has.
  Widget _goneState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This show is no longer in your library.',
          style: TextStyle(color: Xp.text, fontSize: Xp.fontSizeTitle),
        ),
        const SizedBox(height: Xp.spaceS),
        const Text(
          'Its files were removed or matched to another show.',
          style: TextStyle(color: Xp.textDim, fontSize: Xp.fontSizeBody),
        ),
        const SizedBox(height: Xp.spaceL),
        XpButton(
          icon: Icons.arrow_back,
          label: 'Back to library',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  @override
  HeaderSpec buildHeaderSpec() => HeaderSpec(
    // A neutral, TRUE title while the show is gone: the old name would claim
    // a page the library no longer has.
    title: _series == null
        ? 'Not in library'
        : _services.scanning.value
        ? scanningTitle(_series!.displayTitle, _services.scan.progress.value)
        : _series!.displayTitle,
    actions: AppActions(
      scanning: _services.scanning.value,
      unmatchedCount: _services.unmatchedCount.value,
      onScan: _scan,
      onUnmatched: widget.header.onUnmatched,
      onSettings: _openSettings,
      progress: _services.scan.progress.value,
      onStopScan: _services.scanning.value ? _services.scan.stop : null,
    ),
  );

  Widget _content(Series series) {
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
    final q = _episodeQuery.trim().toLowerCase();
    final rows = episodeRowsFor(
      episodes: _episodes,
      hidden: effectiveHidden,
      episodeCount: series.episodeCount,
      showMissing: showMissing,
      query: q,
    );
    final visibleHidden = q.isEmpty
        ? hiddenSorted
        : [
            for (final n in hiddenSorted)
              if (episodeMatchesQuery(number: n, query: q)) n,
          ];
    final ready = !_loading && !_error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Unreachable-files banner (cached info stays visible below it). Two
        // causes, two remedies: a missing drive wants a cable, a denied
        // category wants System Settings.
        if (_unreachable == _Unreachable.denied && ready)
          XpBanner(
            icon: Icons.lock_outline,
            message:
                "AniLocal can't read this show's folder — grant access in "
                'System Settings › Privacy & Security › Files and Folders.',
            actions: [
              XpButton(
                dense: true,
                icon: Icons.settings,
                label: 'Open Settings',
                onPressed: () => fireAndForget(
                  'open access settings',
                  _services.settingsActions.sources.onOpenAccessSettings,
                ),
              ),
              XpButton(
                dense: true,
                icon: Icons.refresh,
                label: 'Try again',
                onPressed: _reload,
              ),
            ],
          ),
        if (_unreachable == _Unreachable.missing && ready)
          XpBanner(
            icon: Icons.link_off,
            message:
                "This show's drive isn't connected — reconnect it to play or "
                'change files.',
            actions: [
              XpButton(
                dense: true,
                icon: Icons.refresh,
                label: 'Try again',
                onPressed: _reload,
              ),
            ],
          ),
        Expanded(
          child: XpScrollbar(
            controller: _scroll,
            // Slivers, not a Column inside a ListView: a 1,000-episode show
            // used to build 1,000 tiles on every keystroke of the search.
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(Xp.spaceL),
                  sliver: SliverToBoxAdapter(
                    child: _pageHeader(series, tally, hiddenSorted, ready),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(Xp.spaceXl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_error)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Xp.spaceL),
                    sliver: SliverToBoxAdapter(child: _errorState()),
                  )
                else if (_viewingHidden && hiddenTabAvailable)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Xp.spaceL),
                    sliver: SliverToBoxAdapter(
                      child: _hiddenView(visibleHidden, q),
                    ),
                  )
                else
                  ..._episodeSlivers(rows, q),
                const SliverToBoxAdapter(child: SizedBox(height: Xp.spaceL)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Cover + titles + metadata + downloaded indicator + Play next + the
  /// Episodes/Hidden toggle + the search field.
  Widget _pageHeader(
    Series series,
    DownloadTally tally,
    List<int> hiddenSorted,
    bool ready,
  ) {
    final hiddenTabAvailable =
        _missingEnabled && !series.pending && hiddenSorted.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover through the show's picture mode (blur/removed apply here
            // too, consistently with the grid + player).
            XpBevel(
              raised: false,
              color: Xp.well,
              child: SizedBox(
                width: 150,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ShowCover(
                    imagePath: series.coverImageRef,
                    pictureMode: series.pictureMode,
                    placeholderIcon: series.pending
                        ? Icons.hourglass_empty
                        : Icons.movie_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Xp.spaceL),
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
                  const SizedBox(height: Xp.spaceS),
                  Text(
                    series.pending
                        ? 'Identifying… (not yet matched)'
                        : [
                            if (series.format != null) series.format,
                            if (series.episodeCount != null)
                              '${series.episodeCount} episodes',
                            if (series.externalIds.anilist != null)
                              'AniList #${series.externalIds.anilist}',
                          ].join(' · '),
                    style: const TextStyle(
                      color: Xp.textDim,
                      fontSize: Xp.fontSizeBody,
                    ),
                  ),
                  if (!series.pending && ready)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: DownloadTallyLabel(tally),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Xp.spaceL),
        if (_next != null && ready)
          Align(
            alignment: Alignment.centerLeft,
            child: XpButton(
              icon: Icons.play_arrow,
              label: 'Play next: ${_next!.displayTitle}',
              onPressed: () => _play(_next!),
            ),
          ),
        const SizedBox(height: Xp.spaceM),
        // Episodes header + Episodes/Hidden tab toggle.
        Row(
          children: [
            const Text(
              'Episodes',
              style: TextStyle(
                color: Xp.text,
                fontSize: Xp.fontSizeTitle,
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
              const SizedBox(width: Xp.spaceXs),
              XpButton(
                dense: true,
                label: 'Hidden (${hiddenSorted.length})',
                selected: _viewingHidden,
                onPressed: () => setState(() => _viewingHidden = true),
              ),
            ],
          ],
        ),
        const SizedBox(height: Xp.spaceS),
        // Live episode search, pinned below the tab control, above the
        // list — the same component + behavior as the homepage search.
        if (ready)
          LibrarySearchBar(
            controller: _searchController,
            hintText: 'Search episodes',
            onChanged: _setQuery,
            onClear: () {
              _searchController.clear();
              _setQuery('');
            },
          ),
      ],
    );
  }

  /// The error state: a load failure shows this instead of an endless spinner.
  Widget _errorState() {
    return XpPanel(
      inset: true,
      padding: const EdgeInsets.all(Xp.spaceXl),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Xp.warning, size: 32),
          const SizedBox(height: Xp.spaceS),
          const Text(
            "Couldn't load this show's episodes.",
            style: TextStyle(color: Xp.text),
          ),
          const SizedBox(height: Xp.spaceM),
          XpButton(icon: Icons.refresh, label: 'Try again', onPressed: _reload),
        ],
      ),
    );
  }

  /// The Hidden tab.
  Widget _hiddenView(List<int> hiddenSorted, String query) {
    // A search that matches no hidden episode reads as a clean empty state,
    // not a blank list.
    if (hiddenSorted.isEmpty) {
      return _emptyState(
        query.trim().isEmpty ? 'No hidden episodes' : 'No episodes match',
      );
    }
    return HiddenEpisodesView(
      hidden: hiddenSorted,
      selected: _hiddenSelection,
      onSelectionChanged: (sel) => setState(() => _hiddenSelection = sel),
      onUnhide: () => _unhide(_hiddenSelection.toList()..sort()),
    );
  }

  /// A clean centered message in a sunken well — used for empty / no-match
  /// episode lists.
  Widget _emptyState(String message) => XpPanel(
    inset: true,
    child: Padding(
      padding: const EdgeInsets.all(Xp.spaceL),
      child: Center(
        child: Text(message, style: const TextStyle(color: Xp.textDim)),
      ),
    ),
  );

  /// The episode list as slivers inside the sunken well, rows separated by
  /// hairlines; each present tile renders from the Episode its row carries
  /// (never a positional index). Dimmed when the drive is disconnected so the
  /// files-dependent affordances read inert.
  List<Widget> _episodeSlivers(List<EpisodeListRow> rows, String query) {
    if (rows.isEmpty) {
      // Distinguish "nothing here" from "search matched nothing".
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Xp.spaceL),
          sliver: SliverToBoxAdapter(
            child: _emptyState(
              query.trim().isEmpty ? 'No episodes' : 'No episodes match',
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Xp.spaceL),
        sliver: SliverOpacity(
          // Cached list stays visible when disconnected, just dimmed — and
          // INERT: dimming alone left every menu live under a banner saying
          // "reconnect it to change files" (actions fail ABSENT).
          opacity: _sourcesUnavailable ? 0.5 : 1,
          sliver: SliverIgnorePointer(
            ignoring: _sourcesUnavailable,
            sliver: XpInsetSliver(
              sliver: SliverList.separated(
                itemCount: rows.length,
                itemBuilder: (_, i) => _rowTile(rows[i]),
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Xp.divider),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _rowTile(EpisodeListRow row) => switch (row) {
    PresentRow(:final episode) => _episodeTile(episode),
    MissingSingleRow(:final number) => MissingSingleTile(
      number: number,
      onHide: () => unawaited(_hide([number])),
    ),
    MissingBundleRow() => MissingBundleTile(
      bundle: row,
      expanded: _expandedBundles.contains(row.first),
      selected: _bundleSelection[row.first] ?? const <int>{},
      onHideAll: () => unawaited(_hide(row.numbers)),
      onExpand: () => setState(() => _expandedBundles.add(row.first)),
      onSelectionChanged: (sel) =>
          setState(() => _bundleSelection[row.first] = sel),
      onCancel: () => setState(() {
        _expandedBundles.remove(row.first);
        _bundleSelection.remove(row.first);
      }),
      onHideSelected: () => unawaited(
        _hide((_bundleSelection[row.first] ?? const <int>{}).toList()..sort()),
      ),
    ),
  };
}
