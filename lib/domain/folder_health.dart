import 'package:equatable/equatable.dart';

/// A show is "unavailable" iff it has source folders AND every one of them is
/// currently missing — a single connected source keeps a multi-source show
/// playable, so it stays un-greyed. The ONE rule the library grid, the show
/// page's banner and the play guards all apply, so they cannot disagree about
/// which shows are reachable. Pure; the sets come from the folder-health pass.
bool seriesUnavailable(Set<String> sourceFolders, Set<String> missingFolders) =>
    sourceFolders.isNotEmpty && sourceFolders.every(missingFolders.contains);

/// The three distinct readability conditions a library folder can be in. A
/// failed read is NOT automatically a permission problem — an unplugged drive
/// or offline NAS is a different condition with a different fix.
///
/// Lives in the domain (not beside the access seam in `lib/data`) because the
/// folder-health MONITOR reports transitions between these states to the UI,
/// and the UI may not import the data layer. One enum, shared both ways.
enum FolderAccessState {
  /// Readable — freely, or folder-wide access is held.
  accessible,

  /// The path/mount doesn't exist: an unplugged external drive or offline NAS.
  /// Recoverable by reconnecting (no Settings interaction); the folder is a
  /// valid library that's merely offline right now — never forget it.
  missing,

  /// The path exists but reading is blocked (TCC / EPERM / EACCES) — the
  /// Settings → Files-and-Folders recovery flow.
  denied,
}

/// One library folder changing state between two folder-health passes: the
/// event a drive being pulled or plugged back in produces. Emitted by the
/// folder-health monitor; the hook alerts, an automatic scan on reconnect and
/// the player's live switch-back attach to.
class FolderAvailabilityChange extends Equatable {
  const FolderAvailabilityChange({
    required this.path,
    required this.from,
    required this.to,
    required this.at,
  });

  /// The folder's STORED path (the library-folder key, the same one the
  /// greying set carries) — not the current mount, which may differ.
  final String path;
  final FolderAccessState from;
  final FolderAccessState to;

  /// When the pass that saw the new state ran.
  final DateTime at;

  /// The folder's drive came back — the case an automatic scan would act on.
  bool get isReconnect =>
      from == FolderAccessState.missing && to == FolderAccessState.accessible;

  /// The folder's drive went away.
  bool get isDisconnect => to == FolderAccessState.missing;

  @override
  List<Object?> get props => [path, from, to, at];

  @override
  String toString() =>
      'FolderAvailabilityChange($path: ${from.name} → ${to.name} at $at)';
}

/// The transitions between two health passes. A folder present in both with a
/// different state yields ONE change; a folder only in [next] (just added) or
/// only in [previous] (just removed) yields nothing — adding or removing a
/// folder is the user's action, not a drive event. Pure. Output is ordered by
/// path so callers and tests see a stable list.
List<FolderAvailabilityChange> diffFolderHealth(
  Map<String, FolderAccessState> previous,
  Map<String, FolderAccessState> next,
  DateTime at,
) {
  final changes = <FolderAvailabilityChange>[];
  for (final path in next.keys.toList()..sort()) {
    final before = previous[path];
    final after = next[path]!;
    if (before == null || before == after) continue;
    changes.add(
      FolderAvailabilityChange(path: path, from: before, to: after, at: at),
    );
  }
  return changes;
}
