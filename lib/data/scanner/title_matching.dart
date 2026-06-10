import '../../domain/models/series.dart';

/// Result of ranking AniList candidates against a parsed title.
typedef MatchResult = ({Series? series, double score});

/// Below this similarity, the best candidate is treated as no match.
const double kMatchFloor = 0.25;

/// Normalize a title for comparison: lowercase, strip punctuation, collapse
/// whitespace. Keeps alphanumerics and spaces only.
String normalizeTitle(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Similarity of two titles in 0–1: the max of a character-level Levenshtein
/// ratio (catches typos/spacing) and a token-set Dice coefficient (catches word
/// order and partial titles). Both operate on normalized text.
double titleSimilarity(String a, String b) {
  final na = normalizeTitle(a);
  final nb = normalizeTitle(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final lev = _levenshteinRatio(na, nb);
  final dice = _tokenDice(na, nb);
  return lev > dice ? lev : dice;
}

/// Rank [candidates] against [parsedTitle] by best similarity across each
/// candidate's romaji/english/native titles. Returns the best match and its
/// score; below [floor] the match is dropped (series == null).
MatchResult rankCandidates(
  String parsedTitle,
  List<Series> candidates, {
  double floor = kMatchFloor,
}) {
  Series? best;
  var bestScore = 0.0;
  for (final c in candidates) {
    final score = _bestTitleScore(parsedTitle, c);
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  if (best == null || bestScore < floor) {
    return (series: null, score: bestScore);
  }
  return (series: best, score: bestScore);
}

double _bestTitleScore(String parsed, Series candidate) {
  var best = 0.0;
  for (final t in [
    candidate.titles.romaji,
    candidate.titles.english,
    candidate.titles.native,
  ]) {
    if (t == null) continue;
    final s = titleSimilarity(parsed, t);
    if (s > best) best = s;
  }
  return best;
}

double _tokenDice(String a, String b) {
  final sa = a.split(' ').toSet();
  final sb = b.split(' ').toSet();
  if (sa.isEmpty || sb.isEmpty) return 0;
  final intersection = sa.intersection(sb).length;
  return 2 * intersection / (sa.length + sb.length);
}

double _levenshteinRatio(String a, String b) {
  final dist = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - dist / maxLen;
}

int _levenshtein(String a, String b) {
  final m = a.length;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  var curr = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}
