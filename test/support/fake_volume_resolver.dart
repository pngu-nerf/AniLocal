import 'package:anilocal/data/folders/volume_resolver.dart';

/// Shared [VolumeResolver] a test configures directly, with no diskutil:
/// [infoByPath] answers `infoForPath` by longest-prefix match (a path inside a
/// configured mount belongs to that volume), and [mountById] says where a
/// volume UUID is mounted RIGHT NOW (null = not mounted). Together they let a
/// test move a library folder to a new mount name and watch the cache follow
/// the UUID rather than churn.
class FakeVolumeResolver implements VolumeResolver {
  final Map<String, VolumeInfo> infoByPath = {};
  final Map<String, String?> mountById = {};

  @override
  Future<VolumeInfo?> infoForPath(String path) async {
    String? best;
    for (final k in infoByPath.keys) {
      if (path == k || path.startsWith('$k/')) {
        if (best == null || k.length > best.length) best = k;
      }
    }
    return best == null ? null : infoByPath[best];
  }

  @override
  Future<String?> mountPointForVolumeId(String volumeId) async =>
      mountById[volumeId];
}
