import 'package:flutter/material.dart';

import '../../domain/models/episode_list_row.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/episode_row.dart';
import '../widgets/multi_select_list.dart';

/// The missing-episode tiles of the show page: a single ghost, a bundle of
/// consecutive ghosts, the checklist a bundle expands into, and the Hidden
/// tab. Pure presentation over callbacks — the page owns the selection state
/// and the hide/unhide writes, these draw and report.
///
/// Extracted from the show page, where the cluster was ~230 lines of a
/// 1,200-line file that its own maintainability assessment had flagged.

/// A faded, outlined circular badge for a missing episode's number — the
/// shared badge in its ghost variant (so present + missing badges can't drift).
Widget _ghostBadge(int number) =>
    EpisodeNumberBadge(number: number, ghost: true);

/// A single missing episode (a ghost). Three-dots → "Hide missing episode".
class MissingSingleTile extends StatelessWidget {
  const MissingSingleTile({
    super.key,
    required this.number,
    required this.onHide,
  });

  final int number;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Xp.spaceS + Xp.spaceXxs,
      vertical: Xp.spaceS,
    ),
    child: Row(
      children: [
        _ghostBadge(number),
        const SizedBox(width: Xp.spaceM),
        const Expanded(
          child: ChromeLabel(
            'Missing',
            upper: false,
            color: Xp.textFaint,
            fontSize: Xp.fontSizeCaption,
            letterSpacing: 1,
          ),
        ),
        ChromeLabel(
          'Episode $number',
          upper: false,
          color: Xp.textFaint,
          fontSize: Xp.fontSizeLabel,
          letterSpacing: 1,
        ),
        const SizedBox(width: Xp.spaceXs),
        _TileMenu(
          items: [
            MenuItemButton(
              onPressed: onHide,
              child: const Text('Hide missing episode'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A consecutive run of 2+ missing episodes: first on top, last on the bottom,
/// joined by a line ("these two and everything between"). Three-dots →
/// "Hide all" or "Select episodes to hide…" (expands inline).
class MissingBundleTile extends StatelessWidget {
  const MissingBundleTile({
    super.key,
    required this.bundle,
    required this.expanded,
    required this.selected,
    required this.onHideAll,
    required this.onExpand,
    required this.onSelectionChanged,
    required this.onCancel,
    required this.onHideSelected,
  });

  final MissingBundleRow bundle;
  final bool expanded;
  final Set<int> selected;
  final VoidCallback onHideAll;
  final VoidCallback onExpand;
  final ValueChanged<Set<int>> onSelectionChanged;
  final VoidCallback onCancel;
  final VoidCallback onHideSelected;

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Xp.spaceS + Xp.spaceXxs,
            ),
            child: Row(
              children: [
                // The "first —line— last" connector, the height of two entries.
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      const SizedBox(height: Xp.spaceS),
                      _ghostBadge(b.first),
                      Expanded(
                        child: Center(
                          child: Container(width: 2, color: Xp.divider),
                        ),
                      ),
                      _ghostBadge(b.last),
                      const SizedBox(height: Xp.spaceS),
                    ],
                  ),
                ),
                const SizedBox(width: Xp.spaceM),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Xp.spaceM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ChromeLabel(
                          'Episode ${b.first}',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: Xp.fontSizeLabel,
                          letterSpacing: 1,
                        ),
                        ChromeLabel(
                          '${b.numbers.length} missing episodes',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: Xp.fontSizeCaption,
                          letterSpacing: 1,
                        ),
                        ChromeLabel(
                          'Episode ${b.last}',
                          upper: false,
                          color: Xp.textFaint,
                          fontSize: Xp.fontSizeLabel,
                          letterSpacing: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                _TileMenu(
                  items: [
                    MenuItemButton(
                      onPressed: onHideAll,
                      child: const Text('Hide all'),
                    ),
                    MenuItemButton(
                      onPressed: onExpand,
                      child: const Text('Select episodes to hide…'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, Xp.spaceS + 2, Xp.spaceS),
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
                  onSelectionChanged: (sel) =>
                      onSelectionChanged({for (final i in sel) b.numbers[i]}),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    XpButton(dense: true, label: 'Cancel', onPressed: onCancel),
                    const SizedBox(width: Xp.spaceS),
                    XpButton(
                      dense: true,
                      icon: Icons.visibility_off,
                      label: 'Hide selected',
                      onPressed: selected.isEmpty ? null : onHideSelected,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The Hidden tab: every hidden episode individually, with the reusable
/// multi-select + an Unhide button. No confirm dialog — select-then-unhide is
/// the two-step safeguard.
class HiddenEpisodesView extends StatelessWidget {
  const HiddenEpisodesView({
    super.key,
    required this.hidden,
    required this.selected,
    required this.onSelectionChanged,
    required this.onUnhide,
  });

  /// Sorted, already filtered by the page's search.
  final List<int> hidden;
  final Set<int> selected;
  final ValueChanged<Set<int>> onSelectionChanged;
  final VoidCallback onUnhide;

  @override
  Widget build(BuildContext context) => XpPanel(
    inset: true,
    padding: const EdgeInsets.fromLTRB(
      Xp.spaceS + 2,
      6,
      Xp.spaceS + 2,
      Xp.spaceS + 2,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MultiSelectList(
          key: ValueKey('hidden-${hidden.join('-')}'),
          itemCount: hidden.length,
          labelBuilder: (_, i) => Text(
            'Episode ${hidden[i]}',
            style: const TextStyle(color: Xp.text),
          ),
          onSelectionChanged: (sel) =>
              onSelectionChanged({for (final i in sel) hidden[i]}),
        ),
        const SizedBox(height: Xp.spaceS),
        Align(
          alignment: Alignment.centerRight,
          child: XpButton(
            icon: Icons.visibility,
            label: 'Unhide',
            onPressed: selected.isEmpty ? null : onUnhide,
          ),
        ),
      ],
    ),
  );
}

/// The three-dots menu on a missing tile: the same `MenuAnchor` every other
/// menu in the app uses (these two were the only `PopupMenuButton`s, and the
/// only menus dispatching on string tokens).
class _TileMenu extends StatelessWidget {
  const _TileMenu({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, controller, _) => IconButton(
      icon: const Icon(Icons.more_vert, color: Xp.textDim),
      tooltip: 'Missing episode options',
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
    menuChildren: items,
  );
}
