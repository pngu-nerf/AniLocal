import 'package:flutter/material.dart';

/// Root of the AniLocal UI.
///
/// Seam #1: the UI imports only Flutter and `lib/domain` — never AniList,
/// Drift, or scanner types. Stage 0 is an empty shell; the library grid,
/// detail, player, and settings views arrive in later stages.
class AniLocalApp extends StatelessWidget {
  const AniLocalApp({super.key});

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
        body: const Center(child: Text('No library folders yet')),
      ),
    );
  }
}
