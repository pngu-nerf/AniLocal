import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small, dependency-free reusable checkbox multi-select. Rows carry a
/// checkbox and a label; behaviour matches Sheets/Finder/Gmail:
///  - click a row toggles it and sets the anchor,
///  - shift-click selects the contiguous range from the last single-click
///    anchor to the shift-clicked row (shift-click with no anchor = plain
///    toggle),
///  - a select-all header toggles everything; it reads "Deselect all" once all
///    rows are selected (clicking then returns to nothing selected).
///
/// It owns its selection state and reports it via [onSelectionChanged]; the
/// host renders the action button (Hide / Unhide) enabled off that set. Used
/// identically by the bundle hide-expand and the Hidden tab.
class MultiSelectList extends StatefulWidget {
  const MultiSelectList({
    super.key,
    required this.itemCount,
    required this.labelBuilder,
    required this.onSelectionChanged,
    this.initialSelection = const {},
  });

  final int itemCount;

  /// Builds the label widget for row [index].
  final Widget Function(BuildContext context, int index) labelBuilder;

  /// Fires whenever the selected index set changes.
  final ValueChanged<Set<int>> onSelectionChanged;

  final Set<int> initialSelection;

  @override
  State<MultiSelectList> createState() => _MultiSelectListState();
}

class _MultiSelectListState extends State<MultiSelectList> {
  late final Set<int> _selected = {...widget.initialSelection};

  /// The last row toggled by a plain (non-shift) click — the anchor a
  /// subsequent shift-click ranges from.
  int? _anchor;

  bool get _shiftHeld {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool get _allSelected =>
      widget.itemCount > 0 && _selected.length == widget.itemCount;

  void _emit() => widget.onSelectionChanged({..._selected});

  void _onRowTap(int index) {
    setState(() {
      if (_shiftHeld && _anchor != null) {
        // Extend: select the whole contiguous range anchor..index (Gmail-style;
        // additive, anchor unchanged).
        final lo = _anchor! < index ? _anchor! : index;
        final hi = _anchor! < index ? index : _anchor!;
        for (var i = lo; i <= hi; i++) {
          _selected.add(i);
        }
      } else {
        // Plain toggle; this row becomes the new anchor.
        if (!_selected.add(index)) _selected.remove(index);
        _anchor = index;
      }
    });
    _emit();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List<int>.generate(widget.itemCount, (i) => i));
      }
      _anchor = null;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggleSelectAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  // full → check, none → empty, partial → dash (indeterminate).
                  value: _allSelected
                      ? true
                      : (_selected.isEmpty ? false : null),
                  tristate: true,
                  onChanged: (_) => _toggleSelectAll(),
                ),
                Text(_allSelected ? 'Deselect all' : 'Select all'),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        for (var i = 0; i < widget.itemCount; i++)
          InkWell(
            onTap: () => _onRowTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: _selected.contains(i),
                    onChanged: (_) => _onRowTap(i),
                  ),
                  Expanded(child: widget.labelBuilder(context, i)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
