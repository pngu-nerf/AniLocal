import 'package:anilocal/data/metadata/metadata_provider.dart';
import 'package:anilocal/domain/models/external_ids.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';

/// A metadata source whose behaviour the test dictates outright — the chain,
/// the identity rules and the circuit breaker are what is under test, never
/// a real API's wire format. Three test files each carried their own; this
/// is the one. [results] is what a search answers; [answersTitle] instead
/// answers with a single show named after the query (enough for a scan to
/// identify a file); [failure] makes every call throw as that failure.
class FakeMetadataProvider implements MetadataProvider {
  FakeMetadataProvider(
    this.token, {
    this.results = const [],
    this.answersTitle = false,
    this.failure,
    this.configured = true,
    this.fallbackOnly = false,
  });

  @override
  final String token;
  final List<Series> results;
  final bool answersTitle;
  final MetadataFailure? failure;
  final bool configured;
  final bool fallbackOnly;

  /// How many searches reached this source.
  int searchCalls = 0;

  @override
  String get displayName => token;
  @override
  String get idNamespace => token;
  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;
  @override
  Future<bool> isConfigured() async => configured;
  @override
  bool get isFallbackOnly => fallbackOnly;

  @override
  Future<List<Series>> searchCandidates(
    String title, {
    int perPage = 10,
  }) async {
    searchCalls++;
    if (failure != null) {
      throw MetadataException('$token is down', failure: failure!);
    }
    if (answersTitle) {
      return [
        Series(
          seriesId: 1,
          externalIds: const ExternalIds(anilist: 1),
          titles: Titles(romaji: title),
        ),
      ];
    }
    return results;
  }

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) async {
    if (failure != null) {
      throw MetadataException('$token is down', failure: failure!);
    }
    return results;
  }
}
