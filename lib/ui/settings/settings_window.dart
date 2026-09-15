import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../diagnostics/app_log.dart';
import '../../domain/repositories/settings_repository.dart';
import '../metadata_failure_message.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/xp_dialog.dart';
import 'panels/about_panel.dart';
import 'panels/homepage_panel.dart';
import 'panels/library_panel.dart';
import 'panels/playback_panel.dart';
import 'panels/source_list_panel.dart';
import 'panels/sources_panel.dart';
import 'setting_row.dart';
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
/// Being modal, it closes on Done or Escape and NOT on a click outside (the
/// barrier is inert), so a stray click cannot drop a half-typed field. Every
/// control still applies immediately — closing only closes.
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
    model = await SettingsModel.load(
      repository: settings,
      loadUnmatchedCount: actions.loadUnmatchedCount,
    );
  } catch (e, stack) {
    // The one situation you most need Settings › About (an unreadable cache)
    // used to make the ⚙ do nothing and reject unhandled. Say so instead.
    AppLog.error('Settings could not load', error: e, stack: stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't open Settings. ${userFacingMessage(e)}"),
          duration: const Duration(seconds: 8),
        ),
      );
    }
    return const SettingsOutcome.unchanged();
  }
  if (!context.mounted) {
    model.dispose();
    return const SettingsOutcome.unchanged();
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
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
/// app run. Session memory, not a setting.
String? _lastCategory;

Future<List<String>> _folderPaths(SettingsDialogActions actions) async => [
  for (final f in await actions.sources.repository.watchedFolders()) f.path,
];

/// What changed while the window was open, so the screen underneath can catch
/// up. Sources moved INTO settings, and reordering them changes which copy of a
/// duplicated episode plays — a change the caller cannot see for itself.
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

  /// THE category list. Adding one later is an entry here plus its panel —
  /// `SettingsShell` never changes, and nothing else in this file does either.
  ///
  /// Only categories with content are listed; there are no placeholder pages.
  List<SettingsCategory> _categories() => [
    // Sources leads, and so is the landing panel: it is the only category that
    // decides what the library CONTAINS (and, by its order, which copy plays)
    // rather than how it behaves — and with no Sources tab in the header, this
    // window is the only way to it.
    SettingsCategory(
      id: sourcesCategoryId,
      // "Folders": what you own. "Sources" was doing three jobs — library
      // folders, metadata/skip providers, and an episode's file copies.
      label: 'Folders',
      icon: Icons.folder_open,
      // Fills the pane and scrolls itself: it hosts a reorderable list.
      scrollable: false,
      builder: (_) => SourcesPanel(sources: actions.sources),
    ),
    // Distinct from Sources on purpose: that is library folders ("what do I
    // own"), this is metadata sources ("what is this show"). Same interaction,
    // different question, independent failure modes.
    SettingsCategory(
      id: metadataCategoryId,
      label: 'Metadata',
      icon: Icons.travel_explore_outlined,
      scrollable: false, // hosts a reorderable list, like Sources
      builder: (_) => SourceListPanel(
        sources: actions.metadataSources,
        settings: model.repository,
        loadOrder: model.repository.loadMetadataSourceOrder,
        saveOrder: model.repository.setMetadataSourceOrder,
        caption:
            'Top source is used first. The rest are tried only if it fails.',
      ),
    ),
    // Same interaction, different question: this one decides where OP/ED
    // timings come from, and fails independently of metadata.
    SettingsCategory(
      id: skipCategoryId,
      label: 'Skip',
      icon: Icons.fast_forward_outlined,
      scrollable: false,
      builder: (_) => SourceListPanel(
        sources: actions.skipSources,
        settings: model.repository,
        loadOrder: model.repository.loadSkipSourceOrder,
        saveOrder: model.repository.setSkipSourceOrder,
        caption:
            'Top source is used first. The rest are tried only if it has no '
            'data for an episode.',
        extra: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingRow(
              label: 'Ignore skips shorter than',
              subtitle:
                  'An opening runs about 90 seconds, so a very short "skip" is '
                  'usually a source mistaking something else for a theme. '
                  '0 keeps every window.',
              control: SizedBox(
                width: 96,
                child: _SecondsField(
                  seconds: model.minSkipLength.inSeconds,
                  onChanged: model.setMinSkipLength,
                ),
              ),
            ),
            SettingRow(
              label: 'Cross-check sources',
              subtitle:
                  'Ask every source and compare. Two that agree can auto-skip; '
                  'ones that disagree offer a button instead. A source with no '
                  'data for an episode is not a disagreement. Slower.',
              control: SettingSwitch(
                value: model.corroborateSkips,
                onChanged: model.setCorroborateSkips,
              ),
            ),
          ],
        ),
      ),
    ),
    SettingsCategory(
      id: playbackCategoryId,
      label: 'Playback',
      icon: Icons.play_circle_outline,
      builder: (_) => PlaybackPanel(model: model),
    ),
    SettingsCategory(
      id: libraryCategoryId,
      label: 'Library',
      icon: Icons.video_library_outlined,
      builder: (_) => LibraryPanel(model: model, actions: actions),
    ),
    SettingsCategory(
      id: homepageCategoryId,
      label: 'Homepage',
      icon: Icons.home_outlined,
      builder: (_) => HomepagePanel(model: model),
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
      listenable: model,
      builder: (context, _) => LayoutBuilder(
        // The window asks for a fixed 760x520, but CLAMPS to what is actually
        // available: the app's minimum window is 600pt wide, so an unclamped
        // fixed size would be clipped rather than merely tight.
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight.isFinite
              ? math.min(SettingsShell.windowHeight, constraints.maxHeight)
              : SettingsShell.windowHeight,
          child: SettingsShell(
            categories: _categories(),
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

/// A plain seconds field.
///
/// Deliberately not the m:ss control the watched-threshold uses: this is a
/// short duration the user thinks about in seconds ("ignore anything under
/// 30"), and m:ss would make them type a colon to say so.
class _SecondsField extends StatefulWidget {
  const _SecondsField({required this.seconds, required this.onChanged});

  final int seconds;
  final void Function(int) onChanged;

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.seconds}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Committed on blur/submit rather than per keystroke: mid-typing "3" on the
  /// way to "30" is a different setting, and saving it would briefly hide
  /// windows the user never meant to exclude.
  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.seconds}'; // unparseable -> leave it alone
      return;
    }
    final clamped = parsed.clamp(0, minSkipLengthMax.inSeconds);
    _controller.text = '$clamped';
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (hasFocus) {
      if (!hasFocus) _commit();
    },
    child: TextField(
      controller: _controller,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Xp.text, fontSize: Xp.fontSizeLabel),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: 's',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
    ),
  );
}
