import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';
import 'scan_results_screen.dart';

/// Root of the AniLocal UI.
///
/// Seam #1: the UI imports only Flutter and `lib/domain` — never AniList,
/// Drift, or scanner types. The scan results arrive as a domain
/// `Future<List<IdentifiedEpisode>>` from the composition root; the UI has no
/// idea they came from a folder scan + AniList matching.
class AniLocalApp extends StatelessWidget {
  const AniLocalApp({super.key, required this.resultsFuture});

  final Future<List<IdentifiedEpisode>> resultsFuture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniLocal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('AniLocal — Scan')),
        body: ScanResultsScreen(resultsFuture: resultsFuture),
      ),
    );
  }
}
