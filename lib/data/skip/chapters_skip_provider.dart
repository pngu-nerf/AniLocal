import '../../domain/chapter_skips.dart';
import '../../domain/models/skip_range.dart';
import '../chapters/chapter_reader.dart';
import 'skip_provider.dart';

/// The episode's own file as a skip source.
///
/// Entirely LOCAL: no network, no MAL id, no provider outage to survive — which
/// makes it the one source that keeps working under every failure mode the rest
/// of this app worries about. Where chapters exist they are also exact, having
/// been authored against that specific encode: measured against AniSkip on the
/// reference library they agreed to within about half a second.
///
/// Its limit is coverage, not accuracy — only about 37% of the reference
/// library's files carry chapters at all, and three whole shows carried none.
/// So it complements AniSkip rather than replacing it, which is exactly what an
/// ordered list of sources is for.
class ChaptersSkipProvider implements SkipProvider {
  const ChaptersSkipProvider({this.reader = const ChapterReader()});

  final ChapterReader reader;

  @override
  String get token => kChaptersSource;

  @override
  String get displayName => 'Chapters in the file';

  @override
  bool get requiresClientId => false;

  @override
  String? get setupUrl => null;

  @override
  String? get setupInstructions => null;

  @override
  Future<bool> isConfigured() async => true; // nothing to configure

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    final path = lookup.filePath;
    // No file to read means no answer — not a failure. This source simply has
    // nothing to say about an episode whose file we don't know.
    if (path == null || path.isEmpty) return null;
    final chapters = await reader.read(path);
    if (chapters.isEmpty) return null;
    return inferSkipsFromChapters(chapters.marks, chapters.duration);
  }
}
