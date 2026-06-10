import 'package:flutter/material.dart';

import '../domain/models/sync_summary.dart';
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
    required this.onScan,
  });

  final LibraryRepository repository;
  final Future<SyncSummary> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniLocal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: LibraryScreen(repository: repository, onScan: onScan),
    );
  }
}
