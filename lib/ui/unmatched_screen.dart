import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';
import '../domain/repositories/fix_match_repository.dart';
import '../domain/repositories/library_repository.dart';
import 'fix_match_screen.dart';
import 'window_chrome.dart';

/// Lists files that matched no AniList entry (kept on record across rescans).
/// Tapping one opens fix-match to assign it (the OPM Specials case).
class UnmatchedScreen extends StatefulWidget {
  const UnmatchedScreen({
    super.key,
    required this.repository,
    required this.fixMatch,
  });

  final LibraryRepository repository;
  final FixMatchRepository fixMatch;

  @override
  State<UnmatchedScreen> createState() => _UnmatchedScreenState();
}

class _UnmatchedScreenState extends State<UnmatchedScreen> {
  late Future<List<IdentifiedEpisode>> _files;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _files = widget.repository.unmatchedFiles();
    });
  }

  Future<void> _fix(IdentifiedEpisode f) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FixMatchScreen(
          fixMatch: widget.fixMatch,
          filePaths: [f.filePath],
          prefillQuery: f.parsedTitle,
        ),
      ),
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Inset the back button clear of the traffic lights (hidden title bar).
        leadingWidth: kAppBarLeadingWidth,
        leading: trafficLightBackButton(),
        title: const Text('Unmatched files'),
      ),
      body: FutureBuilder<List<IdentifiedEpisode>>(
        future: _files,
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
                trailing: const Icon(Icons.edit),
                onTap: () => _fix(f),
              );
            },
          );
        },
      ),
    );
  }
}
