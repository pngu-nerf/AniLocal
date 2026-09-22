import 'dart:async';

import 'package:flutter/material.dart';

import '../../../diagnostics/app_log.dart';
import '../../../domain/models/library_folder.dart';
import '../../access_recovery.dart';
import '../../metadata_failure_message.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/guarded.dart';
import '../../widgets/xp_reorderable_list.dart';
import '../settings_actions.dart';
import '../sources_actions.dart';

/// Folders: the watched library folders, in priority order.
///
/// This is the old standalone `FoldersScreen` rehoused in the settings window —
/// same repository calls, same drag-to-reorder, same add/remove. Nothing about
/// how order becomes play-priority moved or changed: `_onReorder` still calls
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
    unawaited(_reload());
  }

  /// Set when a load failed; rendered instead of the spinner. A throw here
  /// used to leave the spinner forever and the error unhandled.
  Object? _loadError;

  Future<void> _reload() => guarded(
    'folders list',
    () async {
      final folders = await widget.sources.repository.watchedFolders();
      if (mounted) {
        setState(() {
          _folders = folders;
          _loadError = null;
        });
      }
    },
    onError: (e) {
      if (mounted) setState(() => _loadError = e);
    },
  );

  void _sayWriteFailed(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("That didn't save. ${userFacingMessage(e)}")),
    );
    unawaited(_reload()); // show what IS stored, not what was attempted
  }

  Future<void> _add() async {
    final ({bool added, String? deniedLabel}) result;
    try {
      result = await widget.sources.onAddFolder();
    } catch (e, stack) {
      // A refused folder (already added, or nested with one that is) says
      // why; anything else says it did not take.
      AppLog.warn('Add folder refused or failed', error: e, stack: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingMessage(e)),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
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

  Future<void> _remove(LibraryFolder folder) =>
      guarded('remove folder', () async {
        await widget.sources.repository.removeFolder(folder);
        await _reload();
      }, onError: _sayWriteFailed);

  /// Drag committed: reorder optimistically, then persist the new priority.
  /// Folder order IS source priority, so this re-ranks the preferred default
  /// source for every Automatic multi-source episode (applied on next read).
  /// (onReorderItem hands back an already-adjusted newIndex — no manual -1.)
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = [...?_folders];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() => _folders = list);
    await guarded(
      'reorder folders',
      () => widget.sources.repository.reorderFolders(list),
      onError: _sayWriteFailed,
    );
  }

  static const _waitTooltip = kWaitForScanTooltip;

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    if (folders == null) {
      final error = _loadError;
      if (error != null) {
        return Center(
          child: Text(
            "Couldn't read the folder list. ${userFacingMessage(error)}",
            style: const TextStyle(color: Xp.textDim),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    // Add / Remove / reorder are OFF while a scan runs: the scan holds the
    // folder list it started with, so a folder added now would silently never
    // be walked and a removed one would be written back by the next batch.
    return ValueListenableBuilder<bool>(
      valueListenable: widget.sources.scanning,
      // Folder health rides along: a row says "not connected" or "access
      // needed" from the same sets the library greys and banners from. The
      // one place folders are managed used to show them all alike.
      builder: (context, scanning, _) => ValueListenableBuilder<Set<String>>(
        valueListenable: widget.sources.missingFolderPaths,
        builder: (context, missing, _) => ValueListenableBuilder<List<String>>(
          valueListenable: widget.sources.accessIssues,
          builder: (context, denied, _) => _body(
            folders,
            scanning: scanning,
            missing: missing,
            denied: denied.toSet(),
          ),
        ),
      ),
    );
  }

  String? _health(LibraryFolder f, Set<String> missing, Set<String> denied) {
    if (missing.contains(f.path)) return 'Not connected';
    final label = widget.sources.categoryLabelOf(f.path);
    if (label != null && denied.contains(label)) {
      return 'Access needed — $kFilesAndFoldersPath';
    }
    return null;
  }

  Widget _body(
    List<LibraryFolder> folders, {
    required bool scanning,
    required Set<String> missing,
    required Set<String> denied,
  }) {
    if (folders.isEmpty) {
      return Center(
        child: XpButton(
          icon: Icons.add,
          label: 'Add a folder',
          tooltip: scanning ? _waitTooltip : null,
          onPressed: scanning ? null : _add,
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
                style: TextStyle(
                  color: Xp.textDim,
                  fontSize: Xp.fontSizeCaption,
                ),
              ),
            ),
            const SizedBox(width: 12),
            XpButton(
              dense: true,
              icon: Icons.create_new_folder_outlined,
              label: 'Add',
              tooltip: scanning ? _waitTooltip : 'Add folder',
              onPressed: scanning ? null : _add,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: XpReorderableList<LibraryFolder>(
            items: folders,
            keyOf: (f) => f.path,
            titleOf: (f) => f.path,
            subtitleOf: (f) => _health(f, missing, denied),
            dimmed: (f) => _health(f, missing, denied) != null,
            firstCaption: 'Preferred source',
            onReorder: _onReorder,
            enabled: !scanning,
            trailingBuilder: (f) => XpButton(
              dense: true,
              icon: Icons.delete_outline,
              tooltip: scanning
                  ? _waitTooltip
                  : 'Remove (drops its cached files)',
              onPressed: scanning ? null : () => _remove(f),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kept out of [SourcesPanel] so the Library panel's "Edit sources" row and the
