import 'dart:io';

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

  /// A local source cannot answer about a file it was never given. Like
  /// AniSkip's missing MAL id this is "could not try", not "no data": the
  /// scan path has the path and the refresh path gained it later, so recording
  /// an answer from a lookup without one would freeze the wrong result.
  @override
  bool canAnswer(SkipLookup lookup) {
    final path = lookup.filePath;
    if (path == null || path.isEmpty) return false;
    // The file must be THERE. A drive that is unplugged or remounted elsewhere
    // makes the path dangle, and `ChapterReader` reports a missing file as "no
    // chapters" — which the fill path would then record as this source's
    // permanent answer and never ask again. One refresh with the library
    // offline used to erase chapter skips for every episode on that drive,
    // silently. Existence is checked here, where "could not try" is the
    // meaning that stops the row being written.
    return File(path).existsSync();
  }

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    final path = lookup.filePath;
    if (path == null || path.isEmpty) return null;
    final chapters = await reader.read(path);
    if (chapters.isEmpty) return null;
    return inferSkipsFromChapters(chapters.marks, chapters.duration);
  }
}
