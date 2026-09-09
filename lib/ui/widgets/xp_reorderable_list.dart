import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// A drag-to-reorder priority list in the instrument style.
///
/// ONE implementation, shared by the Sources panel (library folders) and the
/// Metadata panel (metadata sources). Both express the same idea — an ordered
/// list where the top entry wins and the rest are fallbacks — so building a
/// second version would guarantee the two drift apart (CLAUDE.md: reuse before
/// you build, make it configurable per location).
///
/// Rows are identified by [keyOf], never by index, so reordering and filtering
/// can't mis-target an action.
class XpReorderableList<T> extends StatelessWidget {
  const XpReorderableList({
    super.key,
    required this.items,
    required this.keyOf,
    required this.titleOf,
    required this.onReorder,
    this.subtitleOf,
    this.firstCaption,
    this.leadingBuilder,
    this.trailingBuilder,
    this.dimmed,
  });

  final List<T> items;

  /// Stable identity for the row — its path, its token, never its position.
  final Object Function(T item) keyOf;

  final String Function(T item) titleOf;

  /// Optional second line. Returning null renders no line at all.
  final String? Function(T item)? subtitleOf;

  /// Caption under the FIRST row, naming what being first means
  /// ("Preferred source", "Source of truth"). Suppressed if a row supplies its
  /// own [subtitleOf], so the two never stack.
  final String? firstCaption;

  /// Before the title — a checkbox, a status lamp. The drag handle is always
  /// drawn first and is not this.
  final Widget Function(T item)? leadingBuilder;

  /// After the title — a remove button, a "Add key" affordance.
  final Widget Function(T item)? trailingBuilder;

  /// Renders a row muted (an off or unavailable source) WITHOUT hiding it: the
  /// user still needs to see it to turn it back on.
  final bool Function(T item)? dimmed;

  /// Receives ALREADY-ADJUSTED indices: `onReorderItem` accounts for the item
  /// being lifted out at [oldIndex], so callers must not subtract one again.
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) => ReorderableListView(
    buildDefaultDragHandles: false,
    onReorderItem: onReorder,
    padding: const EdgeInsets.only(bottom: 4),
    children: [
      for (var i = 0; i < items.length; i++)
        _row(items[i], i, key: ValueKey(keyOf(items[i]))),
    ],
  );

  Widget _row(T item, int index, {required Key key}) {
    final isDim = dimmed?.call(item) ?? false;
    final subtitle =
        subtitleOf?.call(item) ?? (index == 0 ? firstCaption : null);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6),
      child: XpPanel(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_handle, color: Xp.textDim),
              ),
            ),
            const SizedBox(width: 12),
            if (leadingBuilder != null) ...[
              leadingBuilder!(item),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Opacity(
                opacity: isDim ? 0.55 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChromeLabel(
                      titleOf(item),
                      upper: false,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Xp.textDim, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (trailingBuilder != null) trailingBuilder!(item),
          ],
        ),
      ),
    );
  }
}
