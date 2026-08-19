import 'package:flutter/material.dart';

import '../../../domain/models/library_folder.dart';
import '../../access_recovery.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../sources_actions.dart';

/// Sources: the watched library folders, in priority order.
///
/// This is the old standalone `FoldersScreen` rehoused in the settings window —
/// same repository calls, same drag-to-reorder, same add/remove. Nothing about
/// how order becomes play-priority moved or changed: [_onReorder] still calls
/// `reorderFolders`, which rewrites `library_folders.sortOrder`, and
/// `_logicalEpisodes` re-reads that on the next query. The page's header "Add"
/// action is the one thing that had to move — a dialog has no app header, so it
/// sits in the panel's own heading row.
class SourcesPanel extends StatefulWidget {
  const SourcesPanel({super.key, required this.sources});

  final SourcesActions sources;

  @override
  State<SourcesPanel> createState() => _SourcesPanelState();
}

class _SourcesPanelState extends State<SourcesPanel> {
  // Held in state (not a FutureBuilder) so drag-reorder can update
  // optimistically. null = still loading.
  List<LibraryFolder>? _folders;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final folders = await widget.sources.repository.watchedFolders();
    if (mounted) setState(() => _folders = folders);
  }

  Future<void> _add() async {
    final result = await widget.sources.onAddFolder();
    if (!mounted) return;
    if (result.deniedLabel != null) {
      await showAccessDeniedDialog(
        context,
        result.deniedLabel!,
        widget.sources.onOpenAccessSettings,
      );
    }
    if (result.added) await _reload();
  }

  Future<void> _remove(LibraryFolder folder) async {
    await widget.sources.repository.removeFolder(folder);
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
    await widget.sources.repository.reorderFolders(list);
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    if (folders == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (folders.isEmpty) {
      return Center(
        child: XpButton(
          icon: Icons.add,
          label: 'Add a source',
          onPressed: _add,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Drag to set priority. When an episode exists in more than one '
                'source, the top one plays.',
                style: TextStyle(color: Xp.textDim, fontSize: 11),
              ),
            ),
            const SizedBox(width: 12),
            XpButton(
              dense: true,
              icon: Icons.create_new_folder_outlined,
              label: 'Add',
              tooltip: 'Add source',
              onPressed: _add,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorderItem: _onReorder,
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              for (var i = 0; i < folders.length; i++)
                Padding(
                  key: ValueKey(folders[i].path),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: XpPanel(
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Icon(Icons.drag_handle, color: Xp.textDim),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}

/// Kept out of [SourcesPanel] so the Library panel's "Edit sources" row and the
/// header's Sources tab name the same category, not two copies of a string.
const String sourcesCategoryId = 'sources';
