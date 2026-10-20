import 'package:anilocal/domain/models/series.dart' show Series;

import '../../domain/models/metadata_failure.dart';
import '../../domain/models/source_preference.dart';
import '../../sync/source_health.dart';
import '../metadata/metadata_provider.dart';
import 'title_matching.dart';

/// Matches a parsed title to a [Series], asking an ORDERED list of providers.
///
/// The first configured provider that answers wins. A provider that fails
/// (down, blocked, offline) is fallen through to the next, which is the whole
/// point: one source being unreachable must not stop a file being identified.
/// A provider that answers with NO candidates has genuinely answered — that is
/// a no-match, not a failure, so the chain stops there rather than shopping the
/// title around until some provider guesses something.
///
/// Within a provider, if the search returns nothing the title is retried with
/// the leading word dropped, then (still nothing) with the TRAILING word
/// dropped — a general fix for unrecognized junk at either end (site-ripper
/// prefixes; a language word or bare group name the parser's noise list does
/// not know) without enumerating them. Each retry runs only after an EMPTY
/// answer, so a title that finds candidates costs one request as before.
///
/// Propagates [MetadataException] when EVERY provider failed, so the caller can
/// still distinguish "lookup failed" (stay pending, retry next scan) from "no
/// match" (confirmed-unmatched, never retried automatically).
class SeriesMatcher {
  const SeriesMatcher({
    required this.providers,
    this.loadOrder,
    this.candidatesPerTitle = 10,
  });

  /// Every source this build ships, in BUILT-IN order.
  final List<MetadataProvider> providers;

  /// The user's saved order/enablement, read fresh on every match rather than
  /// snapshotted — the settings window can reorder sources while the app is
  /// open, and the next scan must honour that without a restart. Null means
  /// "use [providers] as given" (tests, and any caller with no settings store).
  final Future<List<SourcePreference>> Function()? loadOrder;

  final int candidatesPerTitle;

  /// The enabled sources, in the user's order.
  Future<List<MetadataProvider>> activeProviders() async {
    final load = loadOrder;
    return applySourceOrder(
      providers,
      (p) => p.token,
      load == null ? const [] : await load(),
      // A fallback-only source can never lead, whatever the user saved.
      isFallbackOnly: (p) => p.isFallbackOnly,
    );
  }

  /// Identify [title] through the chain.
  ///
  /// [providers] lets a caller that resolves the order ONCE per run pass it in
  /// (a scan asks for hundreds of titles; re-reading the saved order from the
  /// database for each would be hundreds of identical queries, and per-run is
  /// as fresh as the rule needs — the order cannot change mid-scan from the
  /// scan's own point of view). Omitted, it is read fresh, which is what
  /// fix-match wants.
  ///
  /// [health] is the run's circuit breaker: a source it has marked down is
  /// not asked (each ask would be a full timeout), and every outcome here
  /// feeds it. Omitted for a one-off match (fix-match), where one wait is fine.
  Future<MatchResult> match(
    String title, {
    List<MetadataProvider>? providers,
    SourceHealth? health,
  }) async {
    MetadataException? lastFailure;
    var tried = 0;

    for (final provider in providers ?? await activeProviders()) {
      // Not a failure — a provider awaiting a client ID simply isn't available,
      // and must not count towards "everything is down".
      if (!await provider.isConfigured()) continue;
      if (health?.isDown(provider.token) ?? false) continue;
      tried++;
      try {
        final result = await _matchWith(provider, title);
        health?.succeeded(provider.token);
        // Stamped here rather than in ranking: ranking compares titles and has
        // no idea who supplied the candidates.
        return (
          series: result.series,
          score: result.score,
          source: provider.token,
        );
      } on MetadataException catch (e) {
        health?.failed(provider.token, e.failure);
        lastFailure = e;
      }
    }

    if (lastFailure != null) throw lastFailure;

    // Nothing was even tried (no providers, or none configured). Treat it as a
    // FAILURE rather than a no-match: a no-match would flip the file to
    // confirmed-unmatched and it would never be retried automatically, which is
    // the wrong outcome for a configuration problem.
    throw MetadataException(
      tried == 0
          ? 'No metadata source is configured.'
          : 'No metadata source could answer.',
      failure: MetadataFailure.service,
    );
  }

  Future<MatchResult> _matchWith(
    MetadataProvider provider,
    String title,
  ) async {
    List<Series> candidates = const [];
    for (final query in fallbackQueries(title)) {
      candidates = await provider.searchCandidates(
        query,
        perPage: candidatesPerTitle,
      );
      // Ranked against the query that produced them, not the original: a
      // dropped junk word would only depress every score.
      if (candidates.isNotEmpty) return rankCandidates(query, candidates);
    }
    return rankCandidates(title, candidates);
  }

  /// The queries to try for [title], in order: as given, without its leading
  /// word, without its trailing word. A one-word title yields only itself; a
  /// two-word title yields each word once (both trims give a distinct word).
  static List<String> fallbackQueries(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return [title];
    final withoutLeading = words.sublist(1).join(' ');
    final withoutTrailing = words.sublist(0, words.length - 1).join(' ');
    return [
      title,
      withoutLeading,
      if (withoutTrailing != withoutLeading) withoutTrailing,
    ];
  }
}
