import '../anilist/anilist_client.dart';
import 'title_matching.dart';

/// Matches a parsed title to an AniList [Series] via ranked candidates.
///
/// Searches with the episodic format filter (cuts MUSIC false-positives), and
/// if the search returns nothing, retries once with the leading word dropped —
/// a general fix for unrecognized leading junk (site-ripper prefixes) without
/// enumerating site names. Propagates [AniListException] (transient errors) so
/// the caller can distinguish "lookup failed" from "no match".
class SeriesMatcher {
  const SeriesMatcher({
    required this.anilist,
    this.formatsIn,
    this.candidatesPerTitle = 10,
  });

  final AniListClient anilist;
  final List<String>? formatsIn;
  final int candidatesPerTitle;

  Future<MatchResult> match(String title) async {
    var candidates = await anilist.searchSeriesCandidates(
      title,
      formatsIn: formatsIn,
      perPage: candidatesPerTitle,
    );
    if (candidates.isEmpty) {
      final trimmed = _dropLeadingWord(title);
      if (trimmed != null) {
        candidates = await anilist.searchSeriesCandidates(
          trimmed,
          formatsIn: formatsIn,
          perPage: candidatesPerTitle,
        );
        if (candidates.isNotEmpty) return rankCandidates(trimmed, candidates);
      }
    }
    return rankCandidates(title, candidates);
  }

  static String? _dropLeadingWord(String title) {
    final i = title.indexOf(' ');
    if (i <= 0) return null;
    final rest = title.substring(i + 1).trim();
    return rest.isEmpty ? null : rest;
  }
}
