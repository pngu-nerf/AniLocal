import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/skip_range.dart';

/// A skip source whose behaviour the test dictates: [windows] is its answer
/// (null = it has none), [failure] makes it throw, [answerable] and
/// [configured] gate whether it is asked at all, [onLookup] sees each ask.
/// Two test files each carried their own; this is the one.
class FakeSkipProvider implements SkipProvider {
  FakeSkipProvider(
    this.token, {
    this.windows,
    this.failure,
    this.configured = true,
    this.onLookup,
    this.answerable = true,
    this.readsFile = false,
  });

  @override
  final String token;
  final EpisodeSkips? windows;
  final MetadataFailure? failure;
  final bool configured;
  final bool answerable;
  @override
  final bool readsFile;
  final void Function(SkipLookup)? onLookup;

  /// How many lookups reached this source.
  int calls = 0;

  @override
  String get displayName => token;
  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;
  @override
  Future<bool> canAnswer(SkipLookup lookup) async => answerable;
  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<EpisodeSkips?> fetchSkips(SkipLookup lookup) async {
    calls++;
    onLookup?.call(lookup);
    if (failure != null) throw SkipException('$token down', failure: failure!);
    return windows;
  }
}
