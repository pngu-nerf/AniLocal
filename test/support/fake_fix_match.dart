import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/repositories/fix_match_repository.dart';

/// Shared no-op [FixMatchRepository]: finds no candidates and swallows every
/// assignment. Screen tests need the app assembled with a fix-match seam
/// present, not exercised; the fix-match flow itself has its own tests over
/// the real repository. ONE fake in ONE place — this used to be four
/// byte-identical private copies.
class FakeFixMatch implements FixMatchRepository {
  const FakeFixMatch();

  @override
  Future<List<Series>> searchCandidates(String query) async => const [];
  @override
  Future<void> assignFile({
    required String filePath,
    required Series chosen,
    int? anchoredEpisode,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {}
  @override
  Future<void> assignRange({
    required List<String> filePaths,
    required Series chosen,
    int anchorStart = 1,
    int continuousOffset = 0,
    bool displayContinuous = false,
  }) async {}
  @override
  Future<void> clearOverride(String filePath) async {}
}
