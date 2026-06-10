import 'package:file_selector/file_selector.dart';

import 'folder_access.dart';

/// [FolderPicker] backed by file_selector's `getDirectoryPath`, which drives a
/// native macOS `NSOpenPanel`. The user's selection is what grants access to
/// the (possibly protected) folder — see [FolderAccessToken].
class FileSelectorFolderPicker implements FolderPicker {
  const FileSelectorFolderPicker();

  @override
  Future<FolderAccessToken?> pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Add to library');
    return path == null ? null : FolderAccessToken(path);
  }
}
