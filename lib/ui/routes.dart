import 'package:flutter/widgets.dart';

import '../domain/models/episode.dart';
import '../domain/models/series.dart';
import 'fix_match_screen.dart';
import 'library_services.dart';
import 'series_detail_screen.dart';
import 'shell/instant_page_route.dart';
import 'theater/theater_screen.dart';

/// The hooks a pushed screen needs to render the SAME header as the one it
/// was pushed from: what Scan does and how to open Unmatched (Settings on
/// its Unmatched category, from the screen that owns the settings hooks). One value object rather than
/// three parameters threaded through every screen.
class HeaderHooks {
  const HeaderHooks({required this.onScan, required this.onUnmatched});

  final Future<void> Function() onScan;
  final VoidCallback onUnmatched;
}

/// Every route in the app, constructed in ONE place.
///
/// `TheaterScreen(` was built in two screens with eleven identical arguments,
/// `FixMatchScreen(` in three. Adding a parameter
/// meant editing every site or one screen silently losing it — the exact
/// shape of the settings-bundle bug this codebase already shipped once.
abstract final class AppRoutes {
  /// The show page. Was the one screen still pushed inline (from the card).
  static Future<void> detail(
    BuildContext context, {
    required Series series,
    required LibraryServices services,
    required HeaderHooks header,
  }) => Navigator.of(context).push(
    InstantPageRoute<void>(
      builder: (_) => SeriesDetailScreen(
        series: series,
        services: services,
        header: header,
      ),
    ),
  );

  static Future<void> theater(
    BuildContext context, {
    required LibraryServices services,
    required Series series,
    required Episode episode,
    required HeaderHooks header,
    required Future<void> Function() onSettings,
  }) => Navigator.of(context).push(
    InstantPageRoute<void>(
      builder: (_) => TheaterScreen(
        series: series,
        initialEpisode: episode,
        services: services,
        header: header,
        onSettings: onSettings,
      ),
    ),
  );

  /// Pops `true` when an override was written.
  static Future<bool?> fixMatch(
    BuildContext context, {
    required LibraryServices services,
    required List<String> filePaths,
    required String prefillQuery,
    bool isSplit = false,
    int priorEpisodeCount = 0,
  }) => Navigator.of(context).push<bool>(
    InstantPageRoute<bool>(
      builder: (_) => FixMatchScreen(
        fixMatch: services.fixMatch,
        scanning: services.scanning,
        filePaths: filePaths,
        prefillQuery: prefillQuery,
        isSplit: isSplit,
        priorEpisodeCount: priorEpisodeCount,
      ),
    ),
  );
}
