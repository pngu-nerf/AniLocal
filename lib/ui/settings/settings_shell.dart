import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import 'setting_row.dart';

/// One entry in the settings sidebar, paired with the panel it shows.
///
/// A category is DATA, not a subclass: adding "Audio & Subtitles" later is one
/// more const in the caller's list plus one panel widget — [SettingsShell]
/// itself never changes. The shell has no knowledge of any particular category,
/// and nothing here is per-category special-cased.
///
/// **Only categories with content are passed in.** An empty category is a dead
/// sidebar entry that teaches the user the menu is bigger than it is, so the
/// caller simply omits it rather than the shell rendering a stub.
class SettingsCategory {
  const SettingsCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.scrollable = true,
  });

  /// Stable identity for the selection. NOT an index — the list is filtered by
  /// which categories have content, so a positional key would select the wrong
  /// panel the moment one is omitted.
  final String id;

  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// False for a panel that fills the pane and scrolls ITSELF.
  ///
  /// Most panels are a short column and let the shell scroll them. Sources is
  /// a reorderable list, which needs bounded height and owns its own scrolling
  /// — nesting it inside the shell's scroll view would be an unbounded-height
  /// error and would fight drag-autoscroll. One flag, handled generically; the
  /// shell still has no per-category knowledge.
  final bool scrollable;
}

/// Two-pane settings: a fixed sidebar of categories, and the selected
/// category's panel scrolling beside it.
///
/// Replaces a single scrolling column of collapsibles, which did not scale —
/// every new category made the list longer and pushed everything else further
/// out of reach. Here the panel length is bounded by its category, and the
/// sidebar stays put no matter how far the panel scrolls.
class SettingsShell extends StatefulWidget {
  const SettingsShell({super.key, required this.categories, this.initialId})
    : assert(categories.length > 0, 'the shell needs at least one category');

  final List<SettingsCategory> categories;

  /// Category to open on. Unknown or null falls back to the first, so a
  /// deep-link that names a category which no longer exists still opens a
  /// valid page instead of throwing.
  final String? initialId;

  /// Sidebar width, and the window size the dialog asks for. Kept here so the
  /// shell's proportions live with the shell.
  static const double sidebarWidth = 200;
  static const double windowWidth = 760;
  static const double windowHeight = 520;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  late String _selectedId =
      widget.categories.any((c) => c.id == widget.initialId)
      ? widget.initialId!
      : widget.categories.first.id;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Resolve by IDENTITY, and fall back to the first category rather than
  /// throwing: if a category is ever removed while its panel is showing, the
  /// window degrades to a valid page instead of a crash.
  SettingsCategory get _selected => widget.categories.firstWhere(
    (c) => c.id == _selectedId,
    orElse: () => widget.categories.first,
  );

  void _selectById(String id) {
    if (id == _selectedId) return;
    if (!widget.categories.any((c) => c.id == id)) return;
    setState(() => _selectedId = id);
    // A new panel starts at its top; carrying the old scroll offset across
    // would open the next category part-way down.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _panel(BuildContext context, SettingsCategory selected) {
    const padding = EdgeInsets.fromLTRB(22, 18, 22, 18);
    final heading = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ChromeLabel(
        selected.label,
        color: Xp.text,
        fontSize: 13,
        letterSpacing: 2,
      ),
    );
    if (!selected.scrollable) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            Expanded(child: selected.builder(context)),
          ],
        ),
      );
    }
    return XpScrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, selected.builder(context)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: SettingsShell.sidebarWidth,
          child: ColoredBox(
            color: Xp.well,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              children: [
                for (final c in widget.categories)
                  _SidebarItem(
                    category: c,
                    selected: c.id == selected.id,
                    onTap: () => _selectById(c.id),
                  ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Xp.divider),
        Expanded(
          child: SettingsNavigation(
            select: _selectById,
            // Keyed by category so switching pages rebuilds the panel from
            // scratch instead of reusing the previous one's element state.
            child: KeyedSubtree(
              key: ValueKey(selected.id),
              child: _panel(context, selected),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selected = faint-lit phosphor (the token role for an active segment);
    // unselected sits flush on the black sidebar well.
    final color = selected ? Xp.accent : Xp.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: HoverTap(
          onTap: onTap,
          background: selected ? Xp.accentDeep : Xp.well,
          hoverBackground: selected ? Xp.accentDeep : Xp.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(category.icon, size: 15, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.label,
                    style: TextStyle(color: color, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets a panel move the window to another category — the "Edit sources" row
/// jumping to the Sources tab, for instance.
///
/// An inherited handle rather than a callback threaded into every panel, so
/// [SettingsCategory] stays a plain `WidgetBuilder` and the shell keeps no
/// per-category wiring.
class SettingsNavigation extends InheritedWidget {
  const SettingsNavigation({
    super.key,
    required this.select,
    required super.child,
  });

  final void Function(String categoryId) select;

  static void goTo(BuildContext context, String categoryId) => context
      .dependOnInheritedWidgetOfExactType<SettingsNavigation>()
      ?.select(categoryId);

  @override
  bool updateShouldNotify(SettingsNavigation oldWidget) => false;
}
