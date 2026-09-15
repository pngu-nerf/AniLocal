import 'package:flutter/foundation.dart';

import '../../domain/repositories/library_repository.dart';

/// Everything the Sources tab needs, as ONE injected object.
///
/// Sources moved into the settings window, so its dependencies now have to
/// reach a dialog that opens from two different screens. Bundling them keeps
/// that to a single field rather than threading three more callbacks through
/// the library screen, the series card and the detail screen (CLAUDE.md:
/// "cross-cutting config is injected as ONE object, not threaded").
///
/// [onAddFolder] is the native open-panel, supplied by the composition root —
/// the UI never imports the picker.
class SourcesActions {
  const SourcesActions({
    required this.repository,
    required this.onAddFolder,
    required this.onOpenAccessSettings,
    required this.scanning,
  });

  /// Lists, removes and REORDERS folders. Reordering rewrites
  /// `library_folders.sortOrder`, which is what drives play-priority in
  /// `_logicalEpisodes` — this object just carries the same repository the old
  /// standalone page used; no ordering logic lives in the UI.
  final LibraryRepository repository;

  /// Opens the native folder picker; reports whether added + any denied
  /// category label (same shared result the home banner reflects).
  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  final Future<bool> Function() onOpenAccessSettings;

  /// True while a scan runs. Add / Remove / reorder are disabled then: the
  /// running scan holds the folder list it started with, so a folder added
  /// mid-scan would silently never be walked and a removed one would be
  /// written back by the next batch.
  final ValueListenable<bool> scanning;
}
