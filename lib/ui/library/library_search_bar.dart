import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// Live library search field, pinned full-width below the top bar. Filters the
/// already-cached library as you type (no submit, no network) — the host
/// re-filters its in-memory series list on each [onChanged]. A trailing clear
/// button restores the full library (empty query → everything).
///
/// Styled as a sunken XP "well" so it reads as an editable inset, consistent
/// with the rest of the blackout-XP chrome.
class LibrarySearchBar extends StatelessWidget {
  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search your library',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Placeholder text (e.g. "Search episodes" when reused on the detail page).
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return XpPanel(
      inset: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Xp.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: Xp.accentBright,
              style: const TextStyle(fontSize: 13, color: Xp.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(color: Xp.textFaint, fontSize: 13),
              ),
            ),
          ),
          // Show the clear affordance only when there's something to clear.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : XpButton(
                    dense: true,
                    icon: Icons.close,
                    tooltip: 'Clear search',
                    onPressed: onClear,
                  ),
          ),
        ],
      ),
    );
  }
}
