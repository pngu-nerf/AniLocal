import 'package:flutter/material.dart';

import '../domain/models/series.dart';
import 'metadata_screen.dart';

/// Root of the AniLocal UI.
///
/// Seam #1: the UI imports only Flutter and `lib/domain` — never AniList,
/// Drift, or scanner types. The metadata to show arrives as a `Future<Series>`
/// supplied by the composition root; the UI has no idea it came from AniList.
class AniLocalApp extends StatelessWidget {
  const AniLocalApp({super.key, required this.seriesFuture});

  final Future<Series> seriesFuture;

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
        appBar: AppBar(title: const Text('AniLocal')),
        body: MetadataScreen(seriesFuture: seriesFuture),
      ),
    );
  }
}
