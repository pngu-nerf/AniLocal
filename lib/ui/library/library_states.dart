import 'dart:async';

import 'package:flutter/material.dart';

import '../../diagnostics/app_log.dart';
import '../../domain/models/cache_errors.dart';
import '../metadata_failure_message.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/copy_diagnostics.dart';
import '../widgets/notices.dart';
import '../widgets/xp_error_state.dart';
import '../widgets/xp_message.dart';
import '../window_chrome.dart';

// The library page's whole-page states — no match, could not load, empty —
// each a widget of its own so the page file holds the page. They render
// through the shared XpErrorState / XpMessage, so they are shape and copy,
// not chrome.

/// Shown when the library has shows but the live search matched none.
class NoSearchResults extends StatelessWidget {
  const NoSearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return XpMessage('No shows match “${query.trim()}”.', emphasis: true);
  }
}

/// The library could not be read at all. Distinguishes the ONE failure with
/// a specific remedy (a cache from a newer build → update the app) from every
/// other, and hands the user the log so a report contains evidence.
class LibraryLoadError extends StatefulWidget {
  const LibraryLoadError({
    super.key,
    required this.error,
    this.cachePath,
    this.onReset,
  });

  final Object error;

  /// Where the cache lives — named, so the user knows which file is broken.
  final String? cachePath;

  /// Sets the cache aside (returns the quarantined path); the panel then
  /// quits the app, because a closed database cannot be reopened in place.
  final Future<String> Function()? onReset;

  @override
  State<LibraryLoadError> createState() => _LibraryLoadErrorState();
}

class _LibraryLoadErrorState extends State<LibraryLoadError> {
  String _copyLabel = 'Copy diagnostics';

  /// Where the broken cache went, once reset has run.
  String? _movedTo;
  bool _resetting = false;

  Future<void> _reset() async {
    final reset = widget.onReset;
    if (reset == null || _resetting) return;
    setState(() => _resetting = true);
    try {
      final moved = await reset();
      if (mounted) setState(() => _movedTo = moved);
    } catch (e, stack) {
      AppLog.error('Cache reset failed', error: e, stack: stack);
      if (mounted) {
        setState(() => _resetting = false);
        showFailure(context, "Couldn't reset.", e);
      }
    }
  }

  /// The same report Settings › About produces, with this screen's error
  /// under it — one payload, one set of words (`copyDiagnostics`).
  Future<void> _copy() async {
    final outcome = await copyDiagnostics(extra: '${widget.error}');
    if (mounted) setState(() => _copyLabel = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final newer = error is CacheNewerThanAppException;
    final movedTo = _movedTo;
    return XpErrorState(
      headline: newer
          ? 'This library was created by a newer version of AniLocal.'
          : "Couldn't open the library cache.",
      message: newer ? 'Update the app to open it.' : userFacingMessage(error),
      extra: [
        if (widget.cachePath case final path?) Text('The cache is $path'),
        if (movedTo != null)
          Text(
            'Moved the broken cache to $movedTo. Quit and reopen AniLocal to '
            'start with an empty library; your folders will need to be added '
            'and scanned again.',
          ),
      ],
      actions: [
        XpButton(
          icon: Icons.copy_outlined,
          label: _copyLabel,
          onPressed: _copy,
        ),
        // Only for a cache that IS broken: a newer-schema cache is intact and
        // wants the newer app, not a reset.
        if (!newer && widget.onReset != null && movedTo == null)
          XpButton(
            icon: Icons.restart_alt,
            label: 'Reset library cache',
            onPressed: _resetting ? null : _reset,
          ),
        if (movedTo != null)
          XpButton(
            lit: true,
            icon: Icons.power_settings_new,
            label: 'Quit AniLocal',
            onPressed: () => unawaited(WindowChrome.quit()),
          ),
      ],
    );
  }
}

/// Two different empties, two different next steps: no folders yet → add
/// one; folders but nothing found → the folders are empty or unreadable, so
/// scan again or check them. One copy for both used to send a user whose
/// drive was unplugged to "add your first folder".
class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({
    super.key,
    required this.scanning,
    required this.hasFolders,
    required this.onAddFolder,
    required this.onScan,
  });

  final bool scanning;
  final bool hasFolders;
  final Future<void> Function() onAddFolder;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasFolders
                ? 'Nothing found in your folders.'
                : 'Your library is empty.',
            style: const TextStyle(color: Xp.text, fontSize: Xp.fontSizeTitle),
          ),
          const SizedBox(height: Xp.spaceL),
          if (hasFolders)
            XpButton(
              icon: Icons.sync,
              label: 'Scan',
              onPressed: scanning ? null : onScan,
            )
          else
            XpButton(
              icon: Icons.create_new_folder_outlined,
              label: 'Add your first folder',
              onPressed: scanning ? null : onAddFolder,
            ),
          const SizedBox(height: 10),
          Text(
            hasFolders
                ? 'No video files turned up in the folders you added. If a '
                      'drive is unplugged, reconnect it; otherwise check the '
                      'folders in Settings › Folders.'
                : 'Point AniLocal at a folder of anime — it scans it for you.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Xp.textDim,
              fontSize: Xp.fontSizeBody,
            ),
          ),
        ],
      ),
    );
  }
}
