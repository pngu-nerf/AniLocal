import 'package:equatable/equatable.dart';

/// What the UI needs to know about one metadata source.
///
/// A DESCRIPTOR, not the source itself: `MetadataProvider` lives in
/// `lib/data/metadata` and the UI must never import it (seam #1). The
/// composition root maps each provider to one of these.
class MetadataSource extends Equatable {
  const MetadataSource({
    required this.token,
    required this.displayName,
    this.configured = true,
    this.setupHint,
  });

  /// Stable identity — matches the provider's token and the value persisted in
  /// the user's source order.
  final String token;

  final String displayName;

  /// False for a source that needs something from the user before it can be
  /// used (a client ID). Such a source is still LISTED — hiding it would leave
  /// no way to discover it — but it is skipped by the lookup chain.
  final bool configured;

  /// What the user must do to enable it, e.g. 'Add your MyAnimeList client ID'.
  /// Null when [configured].
  final String? setupHint;

  @override
  List<Object?> get props => [token, displayName, configured, setupHint];
}
