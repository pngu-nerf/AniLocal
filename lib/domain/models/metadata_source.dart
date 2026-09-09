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
    this.requiresClientId = false,
    this.fallbackOnly = false,
    this.setupHint,
    this.setupUrl,
    this.setupInstructions,
  });

  /// Stable identity — matches the provider's token and the value persisted in
  /// the user's source order.
  final String token;

  final String displayName;

  /// True for a source the user must give a client ID before it can be used.
  ///
  /// Deliberately NOT "is it configured": that is state, and a snapshot taken
  /// at startup would go stale the moment a key is pasted. The panel reads the
  /// stored key itself, so the key is the single source of truth and both the
  /// list and the lookup chain read the same one.
  ///
  /// Such a source is still LISTED — hiding it would leave no way to discover
  /// it — but the chain skips it until a key exists.
  final bool requiresClientId;

  /// True for a source too unreliable to be the source of truth. It sorts below
  /// every other source no matter where the user drags it, and the list says so
  /// rather than silently snapping the row back.
  final bool fallbackOnly;

  /// One-line prompt shown under the row when no key is stored.
  final String? setupHint;

  /// Where to create a key, and what to do there — shown in the key dialog so
  /// the user isn't sent hunting. Null unless [requiresClientId].
  final String? setupUrl;
  final String? setupInstructions;

  @override
  List<Object?> get props => [
    token,
    displayName,
    requiresClientId,
    fallbackOnly,
    setupHint,
    setupUrl,
    setupInstructions,
  ];
}
