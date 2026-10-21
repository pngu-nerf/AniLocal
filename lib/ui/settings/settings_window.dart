import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../diagnostics/app_log.dart';
import '../../domain/repositories/settings_repository.dart';
import '../theme/xp_widgets.dart';
import '../widgets/notices.dart';
import '../widgets/xp_dialog.dart';
import 'panels/about_panel.dart';
import 'panels/display_panel.dart';
import 'panels/folders_panel.dart';
import 'panels/maintenance_panel.dart';
import 'panels/playback_panel.dart';
import 'panels/sources_panel.dart';
import 'panels/unmatched_panel.dart';
import 'settings_actions.dart';
import 'settings_categories.dart';
import 'settings_model.dart';
import 'settings_shell.dart';

/// Open the shared app Settings window. Reachable from the homepage title bar
/// and the detail-page title bar; both pass the ONE injected
/// [SettingsRepository] (all settings) + a small [SettingsDialogActions] of
/// per-screen hooks.
///
/// It is a MODAL over the app's single window, not a second macOS window: the
/// app is frameless and owns one persistent shell, so there is no native
/// titlebar to hand a settings window and no second Flutter view to host it.
/// It closes on Done, on Escape and on a click outside — the walkthrough
/// asked for all three. Closing cannot drop a half-typed field: a focused
/// field loses focus as the route goes, and the blur commits (pinned by
/// test). Every control applies immediately — closing only closes.
Future<SettingsOutcome> showAppSettingsDialog(
  BuildContext context, {
  required SettingsRepository settings,
  required SettingsDialogActions actions,
  String? initialCategory,
}) async {
  // Folders now live IN this window, so what used to be the folders page's
  // before/after comparison happens here — once, for both entry points,
  // instead of each caller re-deriving it.
  final List<String> before;
  final SettingsModel model;
  try {
    before = await _folderPaths(actions);
    model = await SettingsModel.load(repository: settings);
  } catch (e, stack) {
    // The one situation you most need Settings › About (an unreadable cache)
    // used to make the ⚙ do nothing and reject unhandled. Say so instead.
    AppLog.error('Settings could not load', error: e, stack: stack);
    if (context.mounted) {
      showFailure(context, "Couldn't open Settings.", e);
    }
    return const SettingsOutcome.unchanged();
  }
  if (!context.mounted) {
    model.dispose();
    return const SettingsOutcome.unchanged();
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _SettingsWindow(
      model: model,
      actions: actions,
      // The category asked for, else the one the user was on last time this
      // session — the window used to open on Folders every time.
      initialCategory: initialCategory ?? _lastCategory,
      onCategoryChanged: (id) => _lastCategory = id,
    ),
  );
  model.dispose();
  // The CLOSING read decides whether the caller rescans. A failure here must
  // not become an unhandled error out of a VoidCallback: the honest answer is
  // "unchanged", logged.
  try {
    final after = await _folderPaths(actions);
    return SettingsOutcome(
      sourceSetChanged: !setEquals(before.toSet(), after.toSet()),
      sourceOrderChanged: !listEquals(before, after),
    );
  } catch (e, stack) {
    AppLog.error(
      'Settings: folder list after close failed',
      error: e,
      stack: stack,
    );
    return const SettingsOutcome.unchanged();
  }
}

/// The category the settings window was on when it last closed, for this
/// app run. Session memory, not a setting. A remembered id that no longer
/// exists (a tab renamed between runs cannot happen within one run, but the
/// shell guards it anyway) lands on the first tab.
String? _lastCategory;

Future<List<String>> _folderPaths(SettingsDialogActions actions) async => [
  for (final f in await actions.sources.repository.watchedFolders()) f.path,
];

/// What changed while the window was open, so the screen underneath can catch
/// up. Folders moved INTO settings, and reordering them changes which source
/// of a duplicated episode plays — a change the caller cannot see for itself.
///
/// The two are distinct because they cost differently: a folder added or
/// removed needs a SCAN (there are files to discover or drop), while a pure
/// reorder only needs a re-read — `_logicalEpisodes` re-resolves every Automatic
/// default from the new `sortOrder` with no rescan and no network.
class SettingsOutcome {
  const SettingsOutcome({
    required this.sourceSetChanged,
    required this.sourceOrderChanged,
  });

  const SettingsOutcome.unchanged()
    : sourceSetChanged = false,
      sourceOrderChanged = false;

  /// A folder was added or removed — rescan.
  final bool sourceSetChanged;

  /// The priority order differs (true for an add/remove too, since the list
  /// itself differs) — at minimum, re-read.
  final bool sourceOrderChanged;
}

class _SettingsWindow extends StatelessWidget {
  const _SettingsWindow({
    required this.model,
    required this.actions,
    this.initialCategory,
    this.onCategoryChanged,
  });

  final SettingsModel model;
  final SettingsDialogActions actions;
  final String? initialCategory;

  /// Told each time the user picks a category, so the window can reopen there.
  final ValueChanged<String>? onCategoryChanged;

  /// THE category list — seven tabs, each the answer to one question (the
  /// ids file names them). Adding one later is an entry here plus its panel —
  /// `SettingsShell` never changes, and nothing else in this file does either.
  ///
  /// Only categories with content are listed; there are no placeholder pages.
  List<SettingsCategory> _categories(int unmatched) => [
    // Folders leads, and so is the landing panel: it is the only category that
    // decides what the library CONTAINS (and, by its order, which source
    // plays) rather than how it behaves — and with no Folders tab in the
    // header, this window is the only way to it.
    SettingsCategory(
      id: foldersCategoryId,
      // "Folders": what you own. "Sources" is the providers tab below, and an
      // episode's own files in the player; it is never a library folder.
      label: 'Folders',
      icon: Icons.folder_open,
      // Fills the pane and scrolls itself: it hosts a reorderable list that
      // can grow.
      scrollable: false,
      builder: (_) => FoldersPanel(sources: actions.sources),
    ),
    // Where information comes from: the metadata list and the skip-timings
    // list, two groups with two orders, shrink-wrapped so the shell scrolls.
    SettingsCategory(
      id: sourcesCategoryId,
      label: 'Sources',
      icon: Icons.travel_explore_outlined,
      builder: (_) => SourcesPanel(model: model, actions: actions),
    ),
    SettingsCategory(
      id: playbackCategoryId,
      label: 'Playback',
      icon: Icons.play_circle_outline,
      builder: (_) => PlaybackPanel(model: model),
    ),
    SettingsCategory(
      id: displayCategoryId,
      label: 'Display',
      icon: Icons.grid_view_outlined,
      builder: (_) => DisplayPanel(model: model, actions: actions),
    ),
    // Library upkeep the header used to push a page for. The label carries
    // the live count so the sidebar says whether there is anything to do.
    SettingsCategory(
      id: unmatchedCategoryId,
      label: unmatched == 0 ? 'Unmatched' : 'Unmatched ($unmatched)',
      icon: Icons.help_outline,
      scrollable: false, // a list that scrolls itself
      builder: (_) => UnmatchedPanel(actions: actions),
    ),
    SettingsCategory(
      id: maintenanceCategoryId,
      label: 'Maintenance',
      icon: Icons.build_outlined,
      builder: (_) => MaintenancePanel(actions: actions),
    ),
    SettingsCategory(
      id: aboutCategoryId,
      label: 'About',
      icon: Icons.info_outline,
      builder: (_) => const AboutPanel(),
    ),
  ];

  @override
  Widget build(BuildContext context) => XpDialog(
    title: 'Settings',
    maxWidth: SettingsShell.windowWidth,
    // The sidebar runs flush to the chassis edge; the panel pads itself.
    contentPadding: EdgeInsets.zero,
    // Rebuilt as a whole on any change so every panel — and the sidebar — sees
    // the same values; the model is the one source while the window is open.
    content: ListenableBuilder(
      listenable: Listenable.merge([model, actions.unmatchedCount]),
      builder: (context, _) => LayoutBuilder(
        // The window asks for a fixed 760x520, but CLAMPS to what is actually
        // available: the app's minimum window is 600pt wide, so an unclamped
        // fixed size would be clipped rather than merely tight.
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight.isFinite
              ? math.min(SettingsShell.windowHeight, constraints.maxHeight)
              : SettingsShell.windowHeight,
          child: SettingsShell(
            categories: _categories(actions.unmatchedCount.value),
            initialId: initialCategory,
            onCategoryChanged: onCategoryChanged,
          ),
        ),
      ),
    ),
    actions: [
      XpButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
    ],
  );
}
