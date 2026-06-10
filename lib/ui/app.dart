import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/models/sync_summary.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import 'library_screen.dart';

/// Root of the AniLocal UI.
///
/// Seam #1: the UI imports only Flutter and `lib/domain` — never AniList,
/// Drift, or scanner/sync types. It gets a [LibraryRepository] (cache read
/// path) and an [onScan] callback (fill path) from the composition root.
class AniLocalApp extends StatelessWidget {
  const AniLocalApp({
    super.key,
    required this.repository,
    required this.fixMatch,
    required this.onScan,
    required this.onAddFolder,
    required this.accessIssues,
    required this.onOpenAccessSettings,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;
  final Future<SyncSummary> Function() onScan;
  final Future<({bool added, String? deniedLabel})> Function() onAddFolder;

  /// Denied TCC category labels — shared by the add-dialog and the banner.
  final ValueListenable<List<String>> accessIssues;

  /// Opens the privacy settings pane (best-effort); the message always also
  /// shows the written path, so a stale link never strands the user.
  final Future<bool> Function() onOpenAccessSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniLocal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: LibraryScreen(
        repository: repository,
        fixMatch: fixMatch,
        onScan: onScan,
        onAddFolder: onAddFolder,
        accessIssues: accessIssues,
        onOpenAccessSettings: onOpenAccessSettings,
      ),
    );
  }
}
