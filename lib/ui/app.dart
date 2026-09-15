import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/refresh_summary.dart';
import '../domain/models/source_descriptor.dart';
import '../domain/models/sync_control.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import '../domain/repositories/missing_episodes_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/show_preferences_repository.dart';
import '../domain/repositories/source_selection_repository.dart';
import '../domain/repositories/watch_order_repository.dart';
import '../domain/repositories/watch_state_repository.dart';
import '../playback/playback_controller.dart';
import 'library_screen.dart';
import 'library_services.dart';
import 'scan_control.dart';
import 'settings/settings_actions.dart';
import 'settings/sources_actions.dart';
import 'shell/app_shell.dart';
import 'shell/header_controller.dart';
import 'shell/header_scope.dart';
import 'theme/xp_theme.dart';
import 'tooltip_dismiss_observer.dart';

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
    required this.categoryLabelOf,
    required this.onOpenAccessSettings,
    this.metadataSources = const [],
    this.skipSources = const [],
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

  /// ALL app-wide settings behind ONE injected object. Passed down like the
  /// other repositories; screens + the settings dialog read/write through it.
  final SettingsRepository settings;

  /// The APP-LIFETIME playback engine, built once at the composition root.
  /// Injected (not constructed per route) so leaving the theater stops the
  /// player instead of destroying it — see [PlaybackController].
  final PlaybackController playback;

  /// Fill path. The `onDiscovered` callback fires mid-scan once newly-seen
  /// files have been written as pending placeholders (before identification),
  /// so the UI can reload and paint them immediately.
  final ScanRunner onScan;

  /// Re-fetch metadata (ids + skip data) for already-cached series, without
  /// scanning files or touching overrides/watch-state. Returns counts.
  final Future<RefreshSummary> Function() onRefreshMetadata;

  /// Metadata sources this build ships, for the Settings > Metadata list.
  /// Descriptors only — the UI never sees a provider (seam #1).
  final List<SourceDescriptor> metadataSources;

  /// Skip sources this build ships, for the Settings > Skip list.
  final List<SourceDescriptor> skipSources;

  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  /// Denied TCC category labels — shared by the add-dialog and the banner.
  final ValueListenable<List<String>> accessIssues;

  /// Labels of library folders whose drive/mount is offline (unplugged drive,
  /// offline NAS) — drives the reconnect banner, NOT the Settings flow.
  final ValueListenable<List<String>> missingFolders;

  /// PATHS of those missing folders — lets the grid grey out shows whose only
  /// sources live there. Same detection as [missingFolders], different shape.
  final ValueListenable<Set<String>> missingFolderPaths;

  /// See [LibraryServices.categoryLabelOf].
  final String? Function(String path) categoryLabelOf;

  /// Opens the privacy settings pane (best-effort); the message always also
  /// shows the written path, so a stale link never strands the user.
  final Future<bool> Function() onOpenAccessSettings;

  @override
  Widget build(BuildContext context) => _AppLifetime(app: this);
}

/// Owns every app-lifetime object and releases it when the tree is torn down.
///
/// The ONE navigator key, the header controller and its two route observers,
/// the scan flag, and the playback engine all live here as State — not as
/// top-level globals (which nothing could dispose, and which forced the test
/// harness to re-implement the shell wiring to get a disposable controller).
/// Mounted above `MaterialApp`, so route pushes/pops can't reach any of it:
/// navigation stops playback ([PlaybackController.stop]); only app teardown
/// ends the engine.
///
/// **Honest limit:** on a hard process exit (macOS Cmd-Q, a kill) Flutter does
/// not unmount the tree, so `dispose` will not run and the OS reclaims instead
/// — which is fine, and is also the case where invoking libmpv teardown is most
/// likely to trip the known media_kit FFI race. It DOES run on hot restart and
/// on any graceful teardown, which is where a leaked engine would actually hurt.
class _AppLifetime extends StatefulWidget {
  const _AppLifetime({required this.app});

  final AniLocalApp app;

  @override
  State<_AppLifetime> createState() => _AppLifetimeState();
}

class _AppLifetimeState extends State<_AppLifetime> {
  /// Dismisses tooltips on every root-navigator transition — the single guard
  /// that keeps a mounted tooltip from crashing during media_kit's fullscreen
  /// enter/exit resize, whatever path triggered it (⛶ / Escape / native).
  final _tooltipDismissObserver = TooltipDismissingRouteObserver();

  /// The ONE navigator the shell wraps, and the header state derived from it.
  /// App-lifetime, like the playback engine — the header must outlive every
  /// route or it isn't hoisted at all.
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _headerController = HeaderController(navigatorKey: _navigatorKey);
  late final _headerRouteObserver = HeaderRouteObserver(_headerController);

  /// Scan state for every header — the running flag, progress and Stop (see
  /// `ScanControl`).
  final _scan = ScanControl();

  /// Live unmatched count for every header (see `LibraryServices`).
  final _unmatchedCount = ValueNotifier<int>(0);

  late final LibraryServices _services = LibraryServices(
    repository: widget.app.repository,
    fixMatch: widget.app.fixMatch,
    watchState: widget.app.watchState,
    sourceSelection: widget.app.sourceSelection,
    watchOrder: widget.app.watchOrder,
    missingEpisodes: widget.app.missing,
    showPreferences: widget.app.showPreferences,
    settings: widget.app.settings,
    playback: widget.app.playback,
    scan: _scan,
    missingFolderPaths: widget.app.missingFolderPaths,
    accessIssues: widget.app.accessIssues,
    categoryLabelOf: widget.app.categoryLabelOf,
    unmatchedCount: _unmatchedCount,
    // The ONE place the app-wide settings bundle is built; each screen's ⚙
    // completes it with its own hooks via `SettingsActions.forScreen`.
    settingsActions: SettingsActions(
      sources: SourcesActions(
        repository: widget.app.repository,
        onAddFolder: widget.app.onAddFolder,
        onOpenAccessSettings: widget.app.onOpenAccessSettings,
        scanning: _scan.scanning,
        missingFolderPaths: widget.app.missingFolderPaths,
        accessIssues: widget.app.accessIssues,
        categoryLabelOf: widget.app.categoryLabelOf,
      ),
      metadataSources: widget.app.metadataSources,
      skipSources: widget.app.skipSources,
      onRefreshMetadata: widget.app.onRefreshMetadata,
      scanning: _scan.scanning,
    ),
  );

  @override
  void dispose() {
    // The ONLY PlaybackController.dispose() call in the app. A route pop must
    // never reach this — it calls stop() instead (see VideoZone.dispose).
    unawaited(widget.app.playback.dispose());
    _headerController.dispose();
    _scan.dispose();
    _unmatchedCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The resize half of the tooltip-crash guard sits ABOVE the Navigator,
    // because fullscreen resizes the window without any route transition for
    // the route observer to see.
    return TooltipDismissOnResize(
      child: MaterialApp(
        title: 'AniLocal',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        // The header observer is typed to PageRoute, so dialogs never register
        // as "the top page" — see HeaderController.
        navigatorObservers: [_tooltipDismissObserver, _headerRouteObserver],
        // The VFD "fine-instrument" theme, applied app-wide so EVERY screen
        // inherits the phosphor palette and legible sans — one cohesive
        // instrument, not per-subtree.
        theme: XpTheme.data().copyWith(
          // NO page transition, on every platform. With the header hoisted and
          // constant, content that slid in underneath it read as inconsistent
          // — and the slide is also what made entering the player look like
          // it swiped in and then settled. Navigation is an instant swap.
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              for (final p in TargetPlatform.values)
                p: const _NoPageTransition(),
            },
          ),
        ),
        // A root DefaultTextStyle from the theme's body role, so ALL body Text
        // inherits the matte-cream treatment by construction — even a subtree
        // that isn't under a Material. ABOVE the Navigator: the window chrome
        // is mounted once here, and the Navigator lives inside its chassis,
        // so a route change animates only content and the header never
        // re-mounts.
        builder: (context, child) => DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: HeaderScope(
            controller: _headerController,
            child: AppShell(controller: _headerController, child: child!),
          ),
        ),
        home: LibraryScreen(
          services: _services,
          onScan: widget.app.onScan,
          accessIssues: widget.app.accessIssues,
          missingFolders: widget.app.missingFolders,
          missingFolderPaths: widget.app.missingFolderPaths,
        ),
      ),
    );
  }
}

/// A page transition that doesn't transition — the new route simply IS there.
class _NoPageTransition extends PageTransitionsBuilder {
  const _NoPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
