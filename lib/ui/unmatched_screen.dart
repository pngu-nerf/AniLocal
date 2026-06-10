import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';
import '../domain/repositories/library_repository.dart';

/// Lists files that scanned but matched no AniList entry. These are kept on
/// record (they persist across rescans) so Stage 5 fix-match can resolve them.
class UnmatchedScreen extends StatelessWidget {
  const UnmatchedScreen({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unmatched files')),
      body: FutureBuilder<List<IdentifiedEpisode>>(
        future: repository.unmatchedFiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data ?? const [];
          if (files.isEmpty) {
            return const Center(child: Text('No unmatched files.'));
          }
          return ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final f = files[i];
              return ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(f.fileName),
                subtitle: Text(
                  'parsed: "${f.parsedTitle}"'
                  '${f.parsedEpisodeNumber != null ? ' · ep ${f.parsedEpisodeNumber}' : ''}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
