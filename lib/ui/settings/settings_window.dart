import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/repositories/settings_repository.dart';
import '../theme/xp_widgets.dart';
import '../widgets/xp_dialog.dart';
import 'panels/homepage_panel.dart';
import 'panels/library_panel.dart';
import 'panels/playback_panel.dart';
import 'settings_actions.dart';
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
/// Being modal, it keeps exactly one dismiss affordance (Done). Every control
/// still applies immediately — Done only closes.
Future<void> showAppSettingsDialog(
  BuildContext context, {
  required SettingsRepository settings,
  required SettingsDialogActions actions,
}) async {
  final model = await SettingsModel.load(
    repository: settings,
    loadUnmatchedCount: actions.loadUnmatchedCount,
  );
  if (!context.mounted) {
    model.dispose();
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _SettingsWindow(model: model, actions: actions),
  );
  model.dispose();
}

class _SettingsWindow extends StatelessWidget {
  const _SettingsWindow({required this.model, required this.actions});

  final SettingsModel model;
  final SettingsDialogActions actions;

  /// THE category list. Adding one later is an entry here plus its panel —
  /// `SettingsShell` never changes, and nothing else in this file does either.
  ///
  /// Only categories with content are listed; there are no placeholder pages.
  List<SettingsCategory> _categories(BuildContext context) => [
    SettingsCategory(
      id: 'playback',
      label: 'Playback',
      icon: Icons.play_circle_outline,
      builder: (_) => PlaybackPanel(model: model),
    ),
    SettingsCategory(
      id: 'library',
      label: 'Library',
      icon: Icons.video_library_outlined,
      builder: (_) => LibraryPanel(model: model, actions: actions),
    ),
    SettingsCategory(
      id: 'homepage',
      label: 'Homepage',
      icon: Icons.home_outlined,
      builder: (_) => HomepagePanel(model: model),
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
      listenable: model,
      builder: (context, _) => LayoutBuilder(
        // The window asks for a fixed 760x520, but CLAMPS to what is actually
        // available: the app's minimum window is 600pt wide, so an unclamped
        // fixed size would be clipped rather than merely tight.
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight.isFinite
              ? math.min(SettingsShell.windowHeight, constraints.maxHeight)
              : SettingsShell.windowHeight,
          child: SettingsShell(categories: _categories(context)),
        ),
      ),
    ),
    actions: [
      XpButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
    ],
  );
}
