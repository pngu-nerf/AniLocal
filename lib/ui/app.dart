import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/show_preferences_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import 'library_screen.dart';
import 'shell/app_shell.dart';
import 'shell/header_controller.dart';
import 'shell/header_scope.dart';
import 'theme/xp_theme.dart';
import 'tooltip_dismiss_observer.dart';
import '../playback/playback_controller.dart';

/// Dismisses tooltips on every root-navigator transition — the single guard that
/// keeps a mounted tooltip from crashing during media_kit's fullscreen
/// enter/exit resize, whatever path triggered it (⛶ / Escape / native). One
/// stable instance so app rebuilds don't churn the navigator's observer list.
final _tooltipDismissObserver = TooltipDismissingRouteObserver();

/// The ONE navigator the shell wraps, and the header state derived from it.
/// App-lifetime, like the playback engine — the header must outlive every route
/// or it isn't hoisted at all.
final _navigatorKey = GlobalKey<NavigatorState>();
final _headerController = HeaderController(navigatorKey: _navigatorKey);
final _headerRouteObserver = HeaderRouteObserver(_headerController);

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
    required this.showPreferences,
    required this.settings,
    required this.playback,
    required this.onScan,
    required this.onRefreshMetadata,
    required this.onAddFolder,
    required this.accessIssues,
    required this.missingFolders,
    required this.missingFolderPaths,
    required this.onOpenAccessSettings,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final WatchStateRepository watchState;
  final SourceSelectionRepository sourceSelection;
  final WatchOrderRepository watchOrder;

  /// Hidden-episode store (missing-episodes feature); sacred across rescans.
  final MissingEpisodesRepository missing;

  /// Per-show preferences store (cover display mode + hide-next-episode); sacred
  /// across rescans (no fill-path writer).
  final ShowPreferencesRepository showPreferences;

  /// ALL app-wide settings behind ONE injected object (was ~20 threaded
  /// load*/set* functions). Passed down like the other repositories; screens +
  /// the settings dialog read/write through it.
  final SettingsRepository settings;

  /// The APP-LIFETIME playback engine, built once at the composition root.
  /// Injected (not constructed per route) so leaving the theater stops the
  /// player instead of destroying it — see [PlaybackController].
  final PlaybackController playback;

  /// Fill path. [onDiscovered] fires mid-scan once newly-seen files have been
  /// written as pending placeholders (before identification), so the UI can
  /// reload and paint them immediately.
  final Future<SyncSummary> Function(void Function() onDiscovered) onScan;

  /// Re-fetch metadata (idMal + skip data) for already-cached series, without
  /// scanning files or touching overrides/watch-state. Returns counts.
  final Future<({int seriesRefreshed, int skipsFetched})> Function()
  onRefreshMetadata;

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
    // Two app-lifetime wrappers, both deliberately ABOVE the Navigator:
    //  - the one playback engine (Slice 1), so routes can't destroy it;
    //  - the resize half of the tooltip-crash guard (Slice 2), because
    //    fullscreen now resizes the window without any route transition for
    //    TooltipDismissingRouteObserver to see.
    return _PlaybackEngineOwner(
      playback: playback,
      child: TooltipDismissOnResize(child: _buildApp(context)),
    );
  }

  Widget _buildApp(BuildContext context) {
    return MaterialApp(
      title: 'AniLocal',
      debugShowCheckedModeBanner: false,
      // Dismiss tooltips on every route transition (fullscreen enter/exit is a
      // root-navigator push/pop) — see TooltipDismissingRouteObserver.
      navigatorKey: _navigatorKey,
      // The header observer is typed to PageRoute, so dialogs never register as
      // "the top page" — see HeaderController.
      navigatorObservers: [_tooltipDismissObserver, _headerRouteObserver],
      // The VFD "fine-instrument" theme, applied app-wide so EVERY screen
      // (theater, folders, fix-match, settings, dialogs) inherits the phosphor
      // palette and legible sans — one cohesive instrument, not per-subtree.
      theme: XpTheme.data(),
      // A root DefaultTextStyle from the theme's body role, so ALL body Text
      // inherits the matte-cream Helvetica-Neue treatment by construction —
      // even any subtree that isn't under a Material. The single source for the
      // body role (the display role is VfdReadout); no widget sets the body
      // font itself. (Material still overrides its own chrome text as usual.)
      // ABOVE the Navigator: the window chrome is mounted once here, and the
      // Navigator lives inside its chassis. A route transition therefore
      // animates only content — the header never re-mounts, so it reads as part
      // of the app rather than part of the page.
      builder: (context, child) => DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: HeaderScope(
          controller: _headerController,
          child: AppShell(child: child!),
        ),
      ),
      home: LibraryScreen(
        repository: repository,
        fixMatch: fixMatch,
        watchState: watchState,
        sourceSelection: sourceSelection,
        watchOrder: watchOrder,
        missing: missing,
        showPreferences: showPreferences,
        settings: settings,
        playback: playback,
        onScan: onScan,
        onRefreshMetadata: onRefreshMetadata,
        onAddFolder: onAddFolder,
        accessIssues: accessIssues,
        missingFolders: missingFolders,
        missingFolderPaths: missingFolderPaths,
        onOpenAccessSettings: onOpenAccessSettings,
      ),
    );
  }
}

/// Holds the ONE app-lifetime [PlaybackController] and releases it when the app
/// tree is torn down — the single `dispose()` in the whole app.
///
/// Why a widget rather than a line in `main()`: `main` has no teardown hook, and
/// the engine's owner should be the thing whose lifetime it matches. Mounted at
/// the very top (above `MaterialApp`), so route pushes/pops can't reach it —
/// which is the entire point of the rearchitecture: navigation stops playback
/// ([PlaybackController.stop]); only app teardown ends the engine.
///
/// **Honest limit:** on a hard process exit (macOS Cmd-Q, a kill) Flutter does
/// not unmount the tree, so this will not run and the OS reclaims instead —
/// which is fine, and is also the case where invoking libmpv teardown is most
/// likely to trip the known media_kit FFI race. It DOES run on hot restart and
/// on any graceful teardown, which is where a leaked engine would actually hurt.
class _PlaybackEngineOwner extends StatefulWidget {
  const _PlaybackEngineOwner({required this.playback, required this.child});

  final PlaybackController playback;
  final Widget child;

  @override
  State<_PlaybackEngineOwner> createState() => _PlaybackEngineOwnerState();
}

class _PlaybackEngineOwnerState extends State<_PlaybackEngineOwner> {
  @override
  void dispose() {
    // The ONLY PlaybackController.dispose() call in the app. A route pop must
    // never reach this — it calls stop() instead (see VideoZone.dispose).
    widget.playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
