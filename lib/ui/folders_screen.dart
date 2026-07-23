import 'package:flutter/material.dart';

import '../domain/models/library_folder.dart';
import '../domain/repositories/library_repository.dart';
import 'access_recovery.dart';
import 'theme/xp_tokens.dart';
import 'theme/xp_widgets.dart';
import 'widgets/xp_screen.dart';

/// Manage the watched library folders. Adding goes through [onAddFolder] (the
/// native open-panel, supplied by the composition root — the UI never imports
/// the picker). Listing/removing go through the repository.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({
    super.key,
    required this.repository,
    required this.onAddFolder,
    required this.onOpenAccessSettings,
  });

  final LibraryRepository repository;

  /// Opens the native folder picker; reports whether added + any denied
  /// category label (same shared result the home banner reflects).
  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;
  final Future<bool> Function() onOpenAccessSettings;

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  // Held in state (not a FutureBuilder) so drag-reorder can update optimistically.
  // null = still loading.
  List<LibraryFolder>? _folders;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final folders = await widget.repository.watchedFolders();
    if (mounted) setState(() => _folders = folders);
  }

  Future<void> _add() async {
    final result = await widget.onAddFolder();
    if (!mounted) return;
    if (result.deniedLabel != null) {
      await showAccessDeniedDialog(
        context,
        result.deniedLabel!,
        widget.onOpenAccessSettings,
      );
    }
    if (result.added) await _reload();
  }

  Future<void> _remove(LibraryFolder folder) async {
    await widget.repository.removeFolder(folder);
    await _reload();
  }

  /// Drag committed: reorder optimistically, then persist the new priority.
  /// Folder order IS source priority, so this re-ranks the preferred default
  /// source for every Automatic multi-source episode (applied on next read).
  /// (onReorderItem hands back an already-adjusted newIndex — no manual -1.)
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = [...?_folders];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() => _folders = list);
    await widget.repository.reorderFolders(list);
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    return XpScreen(
      title: 'Sources',
      trailing: XpTitleTab(
        icon: Icons.create_new_folder_outlined,
        label: 'Add',
        tooltip: 'Add source',
        showLabel: MediaQuery.sizeOf(context).width >= 760,
        onPressed: _add,
      ),
      child: folders == null
          ? const Center(child: CircularProgressIndicator())
          : folders.isEmpty
          ? Center(
              child: XpButton(
                icon: Icons.add,
                label: 'Add a source',
                onPressed: _add,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.low_priority,
                        size: 16,
                        color: Xp.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Drag to set priority — the top source is preferred '
                          'for episodes found in more than one source.',
                          style: const TextStyle(
                            color: Xp.textDim,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    buildDefaultDragHandles: false,
                    onReorderItem: _onReorder,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (var i = 0; i < folders.length; i++)
                        Padding(
                          key: ValueKey(folders[i].path),
                          padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                          child: XpPanel(
                            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                    Icons.drag_handle,
                                    color: Xp.textDim,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ChromeLabel(
                                        folders[i].path,
                                        upper: false,
                                        fontSize: 13,
                                        letterSpacing: 1,
                                      ),
                                      if (i == 0) ...[
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Preferred source',
                                          style: TextStyle(
                                            color: Xp.textDim,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                XpButton(
                                  dense: true,
                                  icon: Icons.delete_outline,
                                  tooltip: 'Remove (drops its cached files)',
                                  onPressed: () => _remove(folders[i]),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
