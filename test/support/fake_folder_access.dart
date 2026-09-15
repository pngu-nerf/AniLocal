import 'package:anilocal/data/folders/folder_access.dart';

/// A [FolderAccess] a test scripts by path prefix: the longest configured
/// prefix wins; anything unconfigured is not category-protected.
class FakeFolderAccess implements FolderAccess {
  final Map<String, FolderAccessResult> byPrefix = {};
  final List<String> asked = [];

  @override
  Future<FolderAccessResult> ensureAccess(String folderPath) async {
    asked.add(folderPath);
    String? best;
    for (final k in byPrefix.keys) {
      if (folderPath == k || folderPath.startsWith('$k/')) {
        if (best == null || k.length > best.length) best = k;
      }
    }
    return best == null
        ? const FolderAccessResult.notApplicable()
        : byPrefix[best]!;
  }
}
