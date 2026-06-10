import '../../domain/models/identified_episode.dart';
import '../anilist/anilist_client.dart';
import 'filename_parser.dart';
import 'folder_scanner.dart';
import 'title_matching.dart';

/// Stage 3 pipeline: scan a folder, parse each filename, and auto-match each
/// distinct title to an AniList [Series] via ranked candidates.
///
/// Auto-match only — no caching/persistence (Stage 4) and no manual fix-match
/// (Stage 5). Output is a flat list of [IdentifiedEpisode] to eyeball.
class LibraryIdentifier {
  LibraryIdentifier({
    required this.scanner,
    required this.parser,
    required this.anilist,
    this.formatsIn,
    this.candidatesPerTitle = 10,
    this.requestSpacing = const Duration(milliseconds: 250),
  });

  final FolderScanner scanner;
  final FilenameParser parser;
  final AniListClient anilist;

  /// Format allow-list for the AniList search (pass episodic formats to cut
  /// MUSIC-type false-positives — see Stage 2 recon).
  final List<String>? formatsIn;
  final int candidatesPerTitle;

  /// Delay between unique-title lookups to stay under AniList's rate limit.
  final Duration requestSpacing;

  Future<List<IdentifiedEpisode>> identifyFolder(String folderPath) async {
    final files = await scanner.findVideoFiles(folderPath);

    final parsed = {for (final f in files) f: parser.parse(_basename(f))};

    // Group by normalized title so AniList is queried once per distinct title,
    // never once per file.
    final samplePerTitle = <String, String>{};
    for (final p in parsed.values) {
      if (p.title.isEmpty) continue;
      samplePerTitle.putIfAbsent(normalizeTitle(p.title), () => p.title);
    }

    final matches = <String, MatchResult>{};
    var first = true;
    for (final entry in samplePerTitle.entries) {
      if (!first) await Future<void>.delayed(requestSpacing);
      first = false;
      matches[entry.key] = await _match(entry.value);
    }

    return [
      for (final f in files)
        _toResult(f, parsed[f]!, matches[normalizeTitle(parsed[f]!.title)]),
    ];
  }

  /// Search + rank for one title. If the search returns nothing and the title
  /// has more than one word, retry once with the leading word dropped — a
  /// general fix for unrecognized leading junk (e.g. site-ripper prefixes)
  /// that pollutes the query, without enumerating site names.
  Future<MatchResult> _match(String title) async {
    var candidates = await anilist.searchSeriesCandidates(
      title,
      formatsIn: formatsIn,
      perPage: candidatesPerTitle,
    );
    if (candidates.isEmpty) {
      final space = title.indexOf(' ');
      if (space > 0) {
        final trimmed = title.substring(space + 1).trim();
        if (trimmed.isNotEmpty) {
          candidates = await anilist.searchSeriesCandidates(
            trimmed,
            formatsIn: formatsIn,
            perPage: candidatesPerTitle,
          );
          if (candidates.isNotEmpty) return rankCandidates(trimmed, candidates);
        }
      }
    }
    return rankCandidates(title, candidates);
  }

  IdentifiedEpisode _toResult(
    String file,
    ParsedFilename p,
    MatchResult? match,
  ) {
    return IdentifiedEpisode(
      filePath: file,
      parsedTitle: p.title,
      parsedEpisodeNumber: p.episodeNumber,
      releaseGroup: p.releaseGroup,
      series: match?.series,
      matchScore: match?.score ?? 0,
    );
  }

  String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? path : path.substring(i + 1);
  }
}
