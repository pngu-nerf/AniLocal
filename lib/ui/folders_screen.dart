import 'package:flutter/material.dart';

import '../domain/models/library_folder.dart';
import '../domain/repositories/library_repository.dart';
import 'access_recovery.dart';

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
  late Future<List<LibraryFolder>> _folders;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _folders = widget.repository.watchedFolders();
    });
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
    if (result.added) _reload();
  }

  Future<void> _remove(LibraryFolder folder) async {
    await widget.repository.removeFolder(folder);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library folders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Add folder',
            onPressed: _add,
          ),
        ],
      ),
      body: FutureBuilder<List<LibraryFolder>>(
        future: _folders,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final folders = snapshot.data ?? const [];
          if (folders.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add a folder'),
              ),
            );
          }
          return ListView(
            children: [
              for (final f in folders)
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(f.path),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove (drops its cached files)',
                    onPressed: () => _remove(f),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
