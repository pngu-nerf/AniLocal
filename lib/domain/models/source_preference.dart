import 'package:equatable/equatable.dart';

/// One row of the user's source list: which source, and whether it is on.
///
/// Identified by the source's stable token (`anilist`, `kitsu`, …) rather than
/// by position, so a saved order survives sources being added, removed or
/// renamed in a later release.
class SourcePreference extends Equatable {
  const SourcePreference({required this.token, this.enabled = true});

  final String token;
  final bool enabled;

  SourcePreference copyWith({bool? enabled}) =>
      SourcePreference(token: token, enabled: enabled ?? this.enabled);

  @override
  List<Object?> get props => [token, enabled];
}

/// Apply a saved [preferences] order to the [available] sources.
///
/// THE one place the ordering rule lives, so the scan, fix-match and the
/// settings list can never disagree about what "first" means.
///
/// Rules, in order of importance:
/// * A source the user has ordered takes that position.
/// * A source NOT in [preferences] — one added by a later release — keeps its
///   built-in position among the leftovers and is **enabled by default**,
///   appended after the ordered ones. Shipping a new source must not leave it
///   silently switched off in every existing install.
/// * A preference naming a source that no longer exists is ignored rather than
///   being an error; the list is user data and outlives any one release.
/// * Disabled sources are dropped entirely when [enabledOnly], which is what
///   the lookup chain wants; the settings UI passes false so it can still show
///   them.
List<T> applySourceOrder<T>(
  List<T> available,
  String Function(T) tokenOf,
  List<SourcePreference> preferences, {
  bool enabledOnly = true,
}) {
  final byToken = {for (final item in available) tokenOf(item): item};
  final seen = <String>{};
  final ordered = <T>[];

  for (final pref in preferences) {
    final item = byToken[pref.token];
    if (item == null) continue; // a source this release no longer ships
    seen.add(pref.token);
    if (enabledOnly && !pref.enabled) continue;
    ordered.add(item);
  }

  // Anything the saved order didn't mention, in its built-in order.
  for (final item in available) {
    if (seen.contains(tokenOf(item))) continue;
    ordered.add(item);
  }
  return ordered;
}

/// Whether [token] is switched on, defaulting to true for a source the saved
/// order doesn't mention (see [applySourceOrder]).
bool isSourceEnabled(String token, List<SourcePreference> preferences) {
  for (final pref in preferences) {
    if (pref.token == token) return pref.enabled;
  }
  return true;
}
