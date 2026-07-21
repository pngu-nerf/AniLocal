import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/skip_mode.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'library_screen.dart';
import 'theme/xp_theme.dart';

/// Root of the AniLocal UI.
///
/// Seam #1: the UI imports only Flutter and `lib/domain` — never AniList,
/// Drift, or scanner/sync types. It gets a [LibraryRepository] (cache read
/// path) and an [onScan] callback (fill path) from the composition root.
class AniLocalApp extends StatelessWidget {
  const AniLocalApp({
    super.key,
    required this.repository,
    required this.fixMatch,
    required this.watchState,
    required this.sourceSelection,
    required this.watchOrder,
    required this.missing,
    required this.loadMissingEnabled,
    required this.setMissingEnabled,
    required this.onScan,
    required this.onRefreshMetadata,
    required this.onAddFolder,
    required this.accessIssues,
    required this.missingFolders,
    required this.missingFolderPaths,
    required this.onOpenAccessSettings,
    required this.loadContinueCollapsed,
    required this.setContinueCollapsed,
    required this.loadAutoPlayNext,
    required this.setAutoPlayNext,
    required this.loadSkipMode,
    required this.setSkipMode,
    required this.loadRailFraction,
    required this.setRailFraction,
    required this.loadPanelFraction,
    required this.setPanelFraction,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (missing-episodes feature); sacred across rescans.
  final MissingEpisodesRepository missing;

  /// The missing-episodes feature toggle (persisted; default on). Off = no ghost
  /// tiles / no Hidden tab / counts ignore hidden state, anywhere.
  final Future<bool> Function() loadMissingEnabled;
  final Future<void> Function(bool enabled) setMissingEnabled;

  /// Fill path. [onDiscovered] fires mid-scan once newly-seen files have been
  /// written as pending placeholders (before identification), so the UI can
  /// reload and paint them immediately.
  final Future<SyncSummary> Function(void Function() onDiscovered) onScan;

  /// Re-fetch metadata (idMal + skip data) for already-cached series, without
  /// scanning files or touching overrides/watch-state. Returns counts.
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;
  final Future<bool> Function() loadContinueCollapsed;
  final Future<void> Function(bool collapsed) setContinueCollapsed;

  /// Auto-play-next setting (persisted); read by the player on episode end.
  final Future<bool> Function() loadAutoPlayNext;
  final Future<void> Function(bool enabled) setAutoPlayNext;

  /// Skip mode (off/button/auto), persisted; read by the player per episode.
  final Future<SkipMode> Function() loadSkipMode;
  final Future<void> Function(SkipMode mode) setSkipMode;

  /// Theater rail width (fraction of total), persisted; the rail divider in the
  /// theater reads it on open and writes it when a drag ends.
  final Future<double> Function() loadRailFraction;
  final Future<void> Function(double fraction) setRailFraction;

  /// Continue-watching panel width (fraction), persisted; the landing-page
  /// analogue of the theater rail fraction.
  final Future<double> Function() loadPanelFraction;
  final Future<void> Function(double fraction) setPanelFraction;

  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  /// Denied TCC category labels — shared by the add-dialog and the banner.
  final ValueListenable<List<String>> accessIssues;

  /// Labels of library folders whose drive/mount is offline (unplugged drive,
  /// offline NAS) — drives the reconnect banner, NOT the Settings flow.
  final ValueListenable<List<String>> missingFolders;

  /// PATHS of those missing folders — lets the grid grey out shows whose only
  /// sources live there. Same detection as [missingFolders], different shape.
  final ValueListenable<Set<String>> missingFolderPaths;

  /// Opens the privacy settings pane (best-effort); the message always also
  /// shows the written path, so a stale link never strands the user.
  final Future<bool> Function() onOpenAccessSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniLocal',
      debugShowCheckedModeBanner: false,
      // The VFD "fine-instrument" theme, applied app-wide so EVERY screen
      // (theater, folders, fix-match, settings, dialogs) inherits the phosphor
      // palette and legible sans — one cohesive instrument, not per-subtree.
      theme: XpTheme.data(),
      // A root DefaultTextStyle from the theme's body role, so ALL body Text
      // inherits the matte-cream Helvetica-Neue treatment by construction —
      // even any subtree that isn't under a Material. The single source for the
      // body role (the display role is VfdReadout); no widget sets the body
      // font itself. (Material still overrides its own chrome text as usual.)
      builder: (context, child) => DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: child!,
      ),
      home: LibraryScreen(
        repository: repository,
        fixMatch: fixMatch,
        watchState: watchState,
        sourceSelection: sourceSelection,
        watchOrder: watchOrder,
        missing: missing,
        loadMissingEnabled: loadMissingEnabled,
        setMissingEnabled: setMissingEnabled,
        onScan: onScan,
        onRefreshMetadata: onRefreshMetadata,
        onAddFolder: onAddFolder,
        accessIssues: accessIssues,
        missingFolders: missingFolders,
        missingFolderPaths: missingFolderPaths,
        onOpenAccessSettings: onOpenAccessSettings,
        loadContinueCollapsed: loadContinueCollapsed,
        setContinueCollapsed: setContinueCollapsed,
        loadAutoPlayNext: loadAutoPlayNext,
        setAutoPlayNext: setAutoPlayNext,
        loadSkipMode: loadSkipMode,
        setSkipMode: setSkipMode,
        loadRailFraction: loadRailFraction,
        setRailFraction: setRailFraction,
        loadPanelFraction: loadPanelFraction,
        setPanelFraction: setPanelFraction,
      ),
    );
  }
}
