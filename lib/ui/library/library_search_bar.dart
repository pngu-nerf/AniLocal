import 'package:flutter/material.dart';

/// Live library search field, pinned full-width below the top bar. Filters the
/// already-cached library as you type (no submit, no network) — the host
/// re-filters its in-memory series list on each [onChanged]. A trailing clear
/// button restores the full library (empty query → everything).
class LibrarySearchBar extends StatelessWidget {
  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search your library',
          prefixIcon: const Icon(Icons.search),
          // Show the clear affordance only when there's something to clear.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear search',
                    onPressed: onClear,
                  ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
