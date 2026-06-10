import 'package:flutter/material.dart';

import 'data/anilist/anilist_client.dart';
import 'data/scanner/folder_scanner.dart';
import 'data/scanner/heuristic_filename_parser.dart';
import 'data/scanner/library_identifier.dart';
import 'ui/app.dart';

/// Stage 3 spike: a hardcoded library folder to scan + identify. No settings UI
/// (Stage 5). Must be a NON-TCC-protected location — not ~/Desktop, ~/Documents,
/// or ~/Downloads (those fail with permission errors unrelated to the scanner).
const String kLibraryPath = '/Users/pngu/anilocal-test/library';

/// Episodic anime formats — applied to the AniList candidate search so MUSIC
/// PVs and other non-episodic noise don't win the match (Stage 2 recon).
const List<String> kEpisodicAnimeFormats = [
  'TV',
  'TV_SHORT',
  'MOVIE',
  'SPECIAL',
  'OVA',
  'ONA',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Composition root: assemble the scan+identify pipeline and hand the UI a
  // domain Future. The UI never sees the scanner or AniList types.
  final identifier = LibraryIdentifier(
    scanner: const FileSystemFolderScanner(),
    parser: const HeuristicFilenameParser(),
    anilist: AniListClient(),
    formatsIn: kEpisodicAnimeFormats,
  );
  runApp(AniLocalApp(resultsFuture: identifier.identifyFolder(kLibraryPath)));
}
