import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/skip_mode.dart';
import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'library_screen.dart';

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
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: LibraryScreen(
        repository: repository,
        fixMatch: fixMatch,
        watchState: watchState,
        sourceSelection: sourceSelection,
        watchOrder: watchOrder,
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
      ),
    );
  }
}
