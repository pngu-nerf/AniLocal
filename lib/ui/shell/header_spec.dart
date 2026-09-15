import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../domain/models/sync_control.dart';

/// What a page wants the ONE hoisted header to show while it is the top route.
///
/// **Data, never widgets.** The header is published from every page rebuild
/// (see `HeaderPublisher`) and the controller drops publishes that are equal to
/// what it already holds. A spec carrying built widgets would compare unequal
/// every frame — `HeaderActionsBar(...)` is a new instance each build — so the
/// header would rebuild continuously. Keeping the spec as comparable data is
/// what makes "republish on every build" cheap, and republishing on every build
/// is what stops live state (the scan spinner) from freezing.
///
/// Note what is NOT here: the **back button**. It is derived from the
/// navigator's real `canPop()`, never from a spec, so a stale or missing spec
/// can't strand the user without a way back. See CLAUDE.md, "Fail toward
/// user-in-control".
/// The readout line while a scan runs — the scan's STATUS, short enough to
/// fit the VFD screen without scrolling: `Identifying 12/340`, `Metadata…`,
/// `Skips 120/600`. It used to be the page title with the status appended;
/// that overflowed, and the marquee restarts on every change, so the counter
/// never scrolled into view. Same on every page.
String scanningTitle(SyncProgress? progress) {
  if (progress == null) return 'Scanning…';
  final phase = progress.phase;
  final label = phase[0].toUpperCase() + phase.substring(1);
  // The metadata pass reports once, as a whole; a count would read 12/12.
  if (phase == 'metadata' || progress.total <= 0) return '$label…';
  return '$label ${progress.done}/${progress.total}';
}

class HeaderSpec extends Equatable {
  const HeaderSpec({this.title, this.actions = const NoActions()});

  /// The readout's context line. NULL means "no valid title" and the readout
  /// falls to its seeking spinner — never to a previous page's title.
  final String? title;

  /// The trailing action cluster. Defaults to [NoActions] so a page that says
  /// nothing gets no actions rather than inheriting someone else's.
  final HeaderActions actions;

  @override
  List<Object?> get props => [title, actions];
}

/// The trailing actions, as data. The shell builds the widgets.
///
/// Sealed so adding a cluster forces every renderer to handle it, rather than
/// silently falling through to "no actions".
sealed class HeaderActions extends Equatable {
  const HeaderActions();
}

/// No trailing actions. Also the FAIL STATE: an action whose page context is
/// uncertain must be absent, because a stale action button still fires its
/// side effect — wrongly hidden is inconvenient, wrongly shown is a trap.
class NoActions extends HeaderActions {
  const NoActions();

  @override
  List<Object?> get props => const [];
}

/// The app-wide action row (Sync / Unmatched / Settings) that home
/// and the detail page carry. [scanning] and [unmatchedCount] are LIVE: they
/// change while the page is mounted, and reach the header because the page
/// republishes on every rebuild.
class AppActions extends HeaderActions {
  const AppActions({
    required this.scanning,
    required this.unmatchedCount,
    required this.onScan,
    required this.onUnmatched,
    required this.onSettings,
    this.progress,
    this.onStopScan,
    this.canScan = true,
  });

  final bool scanning;
  final int unmatchedCount;

  /// False when there is nothing to scan (no folders yet): the tab reads
  /// disabled and says to add a folder first, instead of running a scan of
  /// nothing that ends in a "0 scanned" snackbar.
  final bool canScan;
  final Future<void> Function() onScan;
  final VoidCallback onUnmatched;
  final VoidCallback onSettings;

  /// The running scan's last report, for the Stop button's tooltip and the
  /// readout; null when idle or before the first batch commits.
  final SyncProgress? progress;

  /// Stops the running scan at its next checkpoint, keeping what was
  /// committed. Null when no scan is running (the button is then Scan).
  final VoidCallback? onStopScan;

  @override
  List<Object?> get props => [
    scanning,
    unmatchedCount,
    progress?.done,
    progress?.total,
    progress?.phase,
    onStopScan,
    canScan,
    // Callbacks are stable method tear-offs on the page's State, so they
    // participate in equality without defeating it.
    onScan,
    onUnmatched,
    onSettings,
  ];
}

/// A single page-specific tab (one icon + label), for a page that needs its own
/// action rather than the app-wide row.
class SingleAction extends HeaderActions {
  const SingleAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  List<Object?> get props => [icon, label, tooltip, onPressed];
}
