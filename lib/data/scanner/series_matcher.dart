import '../../domain/models/metadata_failure.dart';
import '../../domain/models/source_preference.dart';
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
/// Within a provider, if the search returns nothing the title is retried once
/// with the leading word dropped — a general fix for unrecognized leading junk
/// (site-ripper prefixes) without enumerating site names.
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

  Future<MatchResult> match(String title) async {
    MetadataException? lastFailure;
    var tried = 0;

    for (final provider in await activeProviders()) {
      // Not a failure — a provider awaiting a client ID simply isn't available,
      // and must not count towards "everything is down".
      if (!await provider.isConfigured()) continue;
      tried++;
      try {
        return await _matchWith(provider, title);
      } on MetadataException catch (e) {
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
    var candidates = await provider.searchCandidates(
      title,
      perPage: candidatesPerTitle,
    );
    if (candidates.isEmpty) {
      final trimmed = _dropLeadingWord(title);
      if (trimmed != null) {
        candidates = await provider.searchCandidates(
          trimmed,
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
